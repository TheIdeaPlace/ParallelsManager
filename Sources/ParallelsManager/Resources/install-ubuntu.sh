#!/usr/bin/env bash
# ============================================================================
# install-ubuntu.sh — a new Ubuntu desktop VM in Parallels, with no questions
# asked by the installer.
#
# Downloads Ubuntu's desktop installer (cached), adds an autoinstall answer
# file to it, creates the VM with prlctl, lets the installer run unattended,
# then snapshots the fresh install (with the VM shut down) and starts it.
#
# Set by Parallels Manager (NewUbuntuVMSheet.swift), or by hand:
#   VM_NAME          the VM's name in Parallels (required)
#   VM_USER          the account in Ubuntu (default: your Mac user name)
#   VM_PASSWORD_FILE a file holding the password; it's deleted once read
#   WORK_DIR         where the installer download is cached
#   UBUNTU_SERIES    default 26.04 (an LTS)
#   ORCA=1           Orca on from the start, at the login screen and after
#   AUTOLOGIN=1      sign in automatically
#   ORCA_KEY_GRAVE=1 the backtick/tilde key becomes Caps Lock (macOS keeps the
#                    real one), and Orca uses its laptop layout, whose Orca
#                    key is Caps Lock
#   NOPASSWD_SUDO=1  sudo without a password (handy for SSH automation)
#   VM_CPUS          processors (default: half this Mac's, 2 to 4)
#   VM_RAM           memory in MB (default: 6144, or 4096 on a Mac with less than 16 GB)
#   VM_DISK_GB       the most the disk can grow to (default: 64)
#
# Needs Parallels Desktop Pro or Business (prlctl create) and Homebrew's
# xorriso and openssl: brew install xorriso openssl
#
# Lessons built in (from the first Ubuntu VMs made for The Chat Place):
# * The desktop installer, not the server one: only it brings the snaps
#   (Firefox, Thunderbird, App Center). Without a browser, sign-ins that open
#   a web page fail.
# * cloud-init stays on: it applies the SSH keys and the time zone at first boot.
# * Never snapshot a running VM: the pause trips Ubuntu's service watchdogs,
#   which signs you out and stops Orca. The snapshot here is taken shut down.
# ============================================================================
set -uo pipefail

say_step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAILED: %s\n' "$*"; exit 1; }

PRLCTL=/usr/local/bin/prlctl
[ -x "$PRLCTL" ] || PRLCTL="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
PRLSRVCTL="$(dirname "$PRLCTL")/prlsrvctl"
[ -x "$PRLSRVCTL" ] || PRLSRVCTL="/Applications/Parallels Desktop.app/Contents/MacOS/prlsrvctl"

VM_NAME="${VM_NAME:-}"
VM_USER="${VM_USER:-$(id -un | tr '[:upper:]' '[:lower:]')}"
WORK_DIR="${WORK_DIR:-$HOME/Library/Application Support/ParallelsManager/UbuntuInstall}"
UBUNTU_SERIES="${UBUNTU_SERIES:-26.04}"
ORCA="${ORCA:-1}"
AUTOLOGIN="${AUTOLOGIN:-1}"
ORCA_KEY_GRAVE="${ORCA_KEY_GRAVE:-0}"
NOPASSWD_SUDO="${NOPASSWD_SUDO:-0}"

# -------------------------------------------------------------- checks ----
[ -n "$VM_NAME" ] || fail "VM_NAME isn't set."
[[ "$VM_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] \
    || fail "\"$VM_USER\" can't be an Ubuntu user name: use lower-case letters, digits, - and _, starting with a letter."
[ -x "$PRLCTL" ] || fail "prlctl wasn't found. Is Parallels Desktop installed?"
"$PRLSRVCTL" info >/dev/null 2>&1 || open -g -a "Parallels Desktop"
for _ in $(seq 1 30); do "$PRLSRVCTL" info >/dev/null 2>&1 && break; sleep 2; done
edition=$("$PRLSRVCTL" info --license 2>/dev/null | sed -n 's/.*edition="\([^"]*\)".*/\1/p')
case "$edition" in
    pro|business|"") ;;
    *) fail "Creating VMs from the command line needs Parallels Desktop Pro or Business (this is \"$edition\")." ;;
esac
if "$PRLCTL" list -a -o name | tail -n +2 | sed 's/[[:space:]]*$//' | grep -Fxq "$VM_NAME"; then
    fail "There's already a VM called \"$VM_NAME\". Choose another name."
fi
XORRISO=$(command -v xorriso || true)
[ -n "$XORRISO" ] || fail "xorriso is missing: brew install xorriso"
OPENSSL=""
for candidate in "$(command -v openssl || true)" /opt/homebrew/opt/openssl@3/bin/openssl \
                 /usr/local/opt/openssl@3/bin/openssl; do
    if [ -x "$candidate" ] && "$candidate" passwd -6 -salt check x >/dev/null 2>&1; then
        OPENSSL="$candidate"; break
    fi
done
[ -n "$OPENSSL" ] || fail "An openssl that makes SHA-512 password hashes is missing (macOS's own can't): brew install openssl"

PASSWORD=""
if [ -n "${VM_PASSWORD_FILE:-}" ] && [ -f "$VM_PASSWORD_FILE" ]; then
    PASSWORD=$(cat "$VM_PASSWORD_FILE"); rm -f "$VM_PASSWORD_FILE"
fi
if [ -z "$PASSWORD" ]; then
    read -r -s -p "Password for $VM_USER in Ubuntu: " PASSWORD; echo
fi
[ -n "$PASSWORD" ] || fail "A password is needed."
HASH=$(printf '%s' "$PASSWORD" | "$OPENSSL" passwd -6 -stdin) || fail "Couldn't hash the password."
unset PASSWORD

case "$(uname -m)" in
    arm64)  ARCH=arm64; BASE="https://cdimage.ubuntu.com/releases/$UBUNTU_SERIES/release" ;;
    x86_64) ARCH=amd64; BASE="https://releases.ubuntu.com/$UBUNTU_SERIES" ;;
    *) fail "This Mac's processor ($(uname -m)) isn't one Ubuntu's desktop installer supports." ;;
esac

# Ubuntu host names: lower case, letters, digits and hyphens.
HOSTNAME_VM=$(printf '%s' "$VM_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-63)
[ -n "$HOSTNAME_VM" ] || HOSTNAME_VM=ubuntu-vm
TIMEZONE=$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')
[ -n "$TIMEZONE" ] || TIMEZONE=UTC

mkdir -p "$WORK_DIR" || fail "Couldn't make $WORK_DIR"
cd "$WORK_DIR" || exit 1

# ------------------------------------------------------------ download ----
say_step "Finding the newest Ubuntu $UBUNTU_SERIES desktop installer for $ARCH"
curl -fsSL -o SHA256SUMS "$BASE/SHA256SUMS" || fail "Couldn't reach $BASE (no internet, or no such release)."
ISO=$(grep -oE "ubuntu-$UBUNTU_SERIES(\.[0-9]+)?-desktop-$ARCH\.iso" SHA256SUMS | sort -uV | tail -1)
[ -n "$ISO" ] || fail "Ubuntu $UBUNTU_SERIES has no desktop installer for $ARCH."
SUM=$(grep " \*\?$ISO\$" SHA256SUMS | head -1 | cut -d' ' -f1)
echo "    $ISO"

verified() { [ -f "$ISO" ] && [ "$(shasum -a 256 "$ISO" | cut -d' ' -f1)" = "$SUM" ]; }
if verified; then
    echo "    Already downloaded, and its checksum matches."
else
    say_step "Downloading it (about 6 GB; a download that stops can be resumed by running this again)"
    curl -fL -C - --progress-bar -o "$ISO" "$BASE/$ISO" || fail "The download didn't finish."
    verified || { rm -f "$ISO"; fail "The download's checksum didn't match, so it was deleted. Try again."; }
    echo "    Checksum matches."
fi

# ------------------------------------------------------ answer file ----
say_step "Writing the install answers"
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-autoinstall.XXXXXX") || exit 1
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$BUILD/nocloud" "$BUILD/grub"
KEYS=""
for pub in "$HOME"/.ssh/*.pub; do
    [ -f "$pub" ] || continue
    KEYS+="      - \"$(tr -d '\n"' < "$pub")\""$'\n'
done
EXTRA_PACKAGES=""
[ "$ORCA_KEY_GRAVE" = 1 ] && EXTRA_PACKAGES+="    - keyd"$'\n'

{
    echo "#cloud-config"
    echo "autoinstall:"
    echo "  version: 1"
    echo "  interactive-sections: []"
    echo "  locale: en_US.UTF-8"
    echo "  keyboard: {layout: us}"
    echo "  timezone: $TIMEZONE"
    echo "  source: {id: ubuntu-desktop}"
    echo "  identity:"
    echo "    hostname: $HOSTNAME_VM"
    echo "    username: $VM_USER"
    echo "    realname: \"$(id -F 2>/dev/null | tr -d '"' || echo "$VM_USER")\""
    echo "    password: '$HASH'"
    echo "  ssh:"
    echo "    install-server: true"
    echo "    allow-pw: true"
    if [ -n "$KEYS" ]; then echo "    authorized-keys:"; printf '%s' "$KEYS"; fi
    echo "  storage:"
    echo "    layout: {name: direct}"
    echo "  codecs: {install: true}"
    echo "  drivers: {install: true}"
    echo "  updates: security"
    echo "  packages:"
    echo "    - curl"
    echo "    - git"
    printf '%s' "$EXTRA_PACKAGES"
    echo "  late-commands:"
    echo "    - bash /cdrom/nocloud/setup.sh"
    echo "  shutdown: poweroff"
} > "$BUILD/nocloud/user-data"
touch "$BUILD/nocloud/meta-data"

# Runs at the end of the install, with the new system at /target. Values are
# filled in here; \$ is left for the script itself.
cat > "$BUILD/nocloud/setup.sh" <<EOF
#!/bin/bash
set -x
T=/target
U=$VM_USER
if [ "$NOPASSWD_SUDO" = 1 ]; then
    echo "\$U ALL=(ALL) NOPASSWD:ALL" > \$T/etc/sudoers.d/90-\$U
    chmod 440 \$T/etc/sudoers.d/90-\$U
fi
# The SSH keys straight into place as well, not only through cloud-init.
mkdir -p \$T/home/\$U/.ssh
cat > \$T/home/\$U/.ssh/authorized_keys <<'KEYS'
$(for pub in "$HOME"/.ssh/*.pub; do [ -f "$pub" ] && cat "$pub"; done)
KEYS
chmod 700 \$T/home/\$U/.ssh; chmod 600 \$T/home/\$U/.ssh/authorized_keys
if [ "$AUTOLOGIN" = 1 ]; then
    mkdir -p \$T/etc/gdm3
    printf '[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=%s\n' "\$U" > \$T/etc/gdm3/custom.conf
fi
# System-wide defaults the user can still change: no screen lock or
# blanking, and Orca's choices.
mkdir -p \$T/etc/dconf/profile \$T/etc/dconf/db/local.d
printf 'user-db:user\nsystem-db:local\n' > \$T/etc/dconf/profile/user
{
    printf '[org/gnome/desktop/session]\nidle-delay=uint32 0\n\n'
    printf '[org/gnome/desktop/screensaver]\nlock-enabled=false\n\n'
    printf '[org/gnome/desktop/a11y]\nalways-show-universal-access-status=true\n\n'
    if [ "$ORCA" = 1 ]; then
        printf '[org/gnome/desktop/a11y/applications]\nscreen-reader-enabled=true\n\n'
    fi
    if [ "$ORCA_KEY_GRAVE" = 1 ]; then
        printf "[org/gnome/orca/default/keybindings]\nkeyboard-layout='laptop'\n\n"
    fi
} > \$T/etc/dconf/db/local.d/00-parallels-manager
curtin in-target -- dconf update
if [ "$ORCA" = 1 ]; then
    # Orca at the login screen too.
    mkdir -p \$T/etc/dconf/db/gdm.d
    printf '[org/gnome/desktop/a11y/applications]\nscreen-reader-enabled=true\n' > \$T/etc/dconf/db/gdm.d/00-orca
    curtin in-target -- dconf update
fi
if [ "$ORCA_KEY_GRAVE" = 1 ]; then
    mkdir -p \$T/etc/keyd
    cat > \$T/etc/keyd/default.conf <<'KEYD'
# The backtick/tilde key is Caps Lock: macOS keeps the real Caps Lock for
# itself, and Orca's laptop layout uses Caps Lock as the Orca key.
[ids]
*

[main]
grave = capslock
KEYD
    curtin in-target -- systemctl enable keyd
fi
# No welcome wizard, and no crash-report password prompts in a test machine.
mkdir -p \$T/home/\$U/.config
echo yes > \$T/home/\$U/.config/gnome-initial-setup-done
sed -i 's/^enabled=1/enabled=0/' \$T/etc/default/apport
curtin in-target -- systemctl disable apport.service
curtin in-target -- chown -R \$U:\$U /home/\$U/.config /home/\$U/.ssh
exit 0
EOF

# ------------------------------------------------------------ remaster ----
say_step "Adding the answers to a copy of the installer"
"$XORRISO" -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg "$BUILD/grub/grub.cfg" >/dev/null 2>&1 \
    || fail "Couldn't read the installer's boot menu."
chmod u+w "$BUILD/grub/grub.cfg"
# Start the first menu entry at once, in autoinstall mode, with the answers
# from the disc. GRUB needs the ; escaped.
perl -0pi -e 's/^set timeout=\d+/set timeout=1/m; s{(linux\s+/casper/vmlinuz)}{$1 autoinstall ds=nocloud\\;s=/cdrom/nocloud/}' "$BUILD/grub/grub.cfg"
grep -q 'autoinstall ds=nocloud\\;s=/cdrom/nocloud/' "$BUILD/grub/grub.cfg" \
    || fail "The installer's boot menu isn't in the expected form, so the answers couldn't be added."
AUTO_ISO="$WORK_DIR/$HOSTNAME_VM-autoinstall.iso"
rm -f "$AUTO_ISO"
"$XORRISO" -indev "$ISO" -outdev "$AUTO_ISO" -map "$BUILD/grub/grub.cfg" /boot/grub/grub.cfg \
    -map "$BUILD/nocloud" /nocloud -boot_image any replay >/dev/null 2>&1 \
    || fail "Couldn't make the installer copy."

# -------------------------------------------------------------- the VM ----
CPUS=$(( $(sysctl -n hw.ncpu) / 2 )); [ "$CPUS" -gt 4 ] && CPUS=4; [ "$CPUS" -lt 2 ] && CPUS=2
MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
MEM_MB=4096; [ "$MEM_GB" -ge 16 ] && MEM_MB=6144
CPUS="${VM_CPUS:-$CPUS}"
MEM_MB="${VM_RAM:-$MEM_MB}"
DISK_GB="${VM_DISK_GB:-64}"
for value in "$CPUS" "$MEM_MB" "$DISK_GB"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "Processors, memory and disk size must be whole numbers (got \"$value\")."
done
# Ubuntu's desktop installer itself needs about 25 GB.
[ "$DISK_GB" -ge 25 ] || fail "A $DISK_GB GB disk is too small for Ubuntu's desktop; choose at least 32 GB."

say_step "Creating \"$VM_NAME\" ($CPUS processors, $((MEM_MB / 1024)) GB of memory, a $DISK_GB GB disk that grows as needed)"
# No disk at first, then one of the chosen size, as the Windows installer does.
"$PRLCTL" create "$VM_NAME" -d ubuntu --no-hdd >/dev/null || fail "prlctl couldn't create the VM."
"$PRLCTL" set "$VM_NAME" --cpus "$CPUS" --memsize "$MEM_MB" \
    --description "Ubuntu $UBUNTU_SERIES desktop, made by Parallels Manager" >/dev/null \
    || fail "Couldn't set $CPUS processors and $MEM_MB MB of memory."
"$PRLCTL" set "$VM_NAME" --device-add hdd --type expand --size $(( DISK_GB * 1024 )) \
    --iface sata --position 0 >/dev/null || fail "Couldn't add the $DISK_GB GB disk."
"$PRLCTL" set "$VM_NAME" --device-bootorder "hdd0 cdrom0" >/dev/null 2>&1 || true
"$PRLCTL" set "$VM_NAME" --device-set cdrom0 --image "$AUTO_ISO" --connect >/dev/null \
    || fail "Couldn't attach the installer."
"$PRLCTL" start "$VM_NAME" >/dev/null || fail "The VM didn't start."

say_step "Installing Ubuntu. This takes 15 to 40 minutes; the VM turns itself off when it's done"
started=$(date +%s)
while :; do
    state=$("$PRLCTL" status "$VM_NAME" 2>/dev/null | awk '{print $NF}')
    [ "$state" = stopped ] && break
    minutes=$(( ($(date +%s) - started) / 60 ))
    if [ "$minutes" -ge 120 ]; then
        fail "The install hasn't finished after two hours. Open the VM's window in Parallels to see why; the VM is left as it is."
    fi
    if [ $(( $(date +%s) - started )) -ge 60 ] && [ $(( ($(date +%s) - started) % 300 )) -lt 30 ]; then
        echo "    still installing, $minutes minutes so far"
    fi
    sleep 30
done
echo "    Installed in $(( ($(date +%s) - started) / 60 )) minutes."

"$PRLCTL" set "$VM_NAME" --device-set cdrom0 --disconnect >/dev/null
rm -f "$AUTO_ISO"
say_step "Taking a snapshot of the fresh install (with the VM off, which is the safe way)"
"$PRLCTL" snapshot "$VM_NAME" --name "Fresh install: Ubuntu $UBUNTU_SERIES desktop" >/dev/null \
    || echo "    The snapshot failed; the VM is fine without it."

say_step "Starting it"
"$PRLCTL" start "$VM_NAME" >/dev/null || fail "The VM didn't start after the install."
MAC=$("$PRLCTL" list -i "$VM_NAME" | sed -n 's/.*net0.*mac=\([0-9A-Fa-f]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')
IP=""
for _ in $(seq 1 60); do
    IP=$(grep -i "$MAC" /Library/Preferences/Parallels/parallels_dhcp_leases 2>/dev/null | tail -1 | cut -d= -f1)
    [ -n "$IP" ] && nc -z -G 2 "$IP" 22 >/dev/null 2>&1 && break
    sleep 5
done

echo ""
echo "========================================================================"
echo "\"$VM_NAME\" is ready: Ubuntu $UBUNTU_SERIES desktop."
echo "  User name: $VM_USER (with the password you chose)"
[ "$AUTOLOGIN" = 1 ] && echo "  It signs in automatically."
[ "$ORCA" = 1 ] && echo "  Orca is on, at the login screen and after."
[ "$ORCA_KEY_GRAVE" = 1 ] && echo "  The backtick/tilde key is Caps Lock, Orca's key in its laptop layout."
if [ -n "$IP" ]; then
    echo "  Address: $IP    SSH: ssh $VM_USER@$IP"
else
    echo "  Its address wasn't found yet; it's in Parallels' list of DHCP leases once it's up."
fi
echo "  Snapshot: \"Fresh install: Ubuntu $UBUNTU_SERIES desktop\" (to go back to)."
echo "========================================================================"
