# Parallels Manager

A native macOS SwiftUI app to manage Parallels Desktop virtual machines — with full VoiceOver accessibility.

## What It Does

Parallels Manager lists all your Parallels Desktop VMs and lets you:

- **Start** a stopped or suspended VM
- **Stop** a running VM (soft shutdown)
- **Pause** a running VM
- **Resume** a paused or suspended VM
- **Clone** a VM (prompts for a new name)
- **Delete** a VM (with confirmation)
- **Remove from List** a VM whose files are gone (Parallels shows it as invalid, and can't start or delete it): Parallels forgets it, and any files that still exist are left alone
- **Create a new Windows 11 ARM VM** (File, New Windows VM…, ⌘N)
- **Create a new Ubuntu desktop VM** (File, New Ubuntu VM…, ⌘⌥N), with no installer questions — see below

The VM list refreshes after each action and with ⌘R (not on a timer, which was taken out as a VoiceOver fix). A busy indicator appears on the row while an operation is in progress.

## Requirements

| Requirement | Notes |
|---|---|
| macOS 13 Ventura or later | Apple Silicon or Intel |
| Parallels Desktop | `/usr/local/bin/prlctl` must be present |
| Xcode Command Line Tools | For building from source (`xcode-select --install`) |
| Developer ID certificate | Only needed for the signed build and DMG |

## Using the App

### With a Mouse or Trackpad

Right-click any VM row to get a context menu with all available actions. The menu only shows actions that are valid for the VM's current state (e.g. Start is greyed out if the VM is already running).

You can also use the **VM Actions** menu in the menu bar. The selected VM (highlighted row) determines which VM the menu commands act on.

### Keyboard Shortcuts (VM Actions menu)

| Action | Shortcut |
|---|---|
| Start | ⌘ Return |
| Stop | ⌘ . |
| Pause | ⌘ ⌥ P |
| Resume | ⌘ ⇧ P |
| Clone… | ⌘ ⇧ D |
| Delete… | ⌘ ⇧ ⌫ |
| Remove from List… | (menu only; for invalid VMs) |

Click a row first so the app knows which VM to act on, then press the shortcut.

### With VoiceOver

Three access paths are available:

1. **VM Actions menu bar menu** — always reachable regardless of where VoiceOver focus is. Select a VM in the list, then open VM Actions from the menu bar.

2. **Context menu (VO + Shift + M)** — move VoiceOver focus to any VM row and press VO + Shift + M to open the context menu for that VM.

3. **Accessibility actions (VO + Z)** — move VoiceOver focus to any VM row and press VO + Z to cycle through quick actions: Start, Stop, Pause, Resume, Clone, Delete, and Remove from List for an invalid VM.

Each VM row reads aloud as: **"[Name], [status]"** with a hint pointing to the context menu and action rotor.

## Processors, memory and disk

Both New VM dialogs have three pop-up menus, after the name fields:

- **Processors:** from 1 to as many as this Mac has.
- **Memory:** from 2 GB up to this Mac's memory less 4 GB, which is always left for the Mac itself.
- **Disk size:** 32, 64, 128, 256 or 512 GB. That's the most the disk can grow to; it takes up only what's used.

New Windows VM starts at 6 processors, 8 GB and 128 GB; New Ubuntu VM at 4 processors, 6 GB and 64 GB (on a Mac with less than 16 GB, 4 GB). Both are brought down to what a smaller Mac can give.

## New Ubuntu VM

File, **New Ubuntu VM…** (⌘⌥N) makes an Ubuntu 26.04 LTS desktop VM without the installer asking anything. Give it a name, the Ubuntu user name and password, its processors, memory and disk size (see below), and choose:

- **Orca screen reader on from the start**, at the login screen and after.
- **Sign in automatically.**
- **Backtick key is Caps Lock, Orca's key.** macOS keeps the real Caps Lock for itself, so the backtick/tilde key takes its place (through keyd, the way SharpKeys does on Windows), and Orca uses its laptop layout, whose Orca key is Caps Lock. The VM then can't type a backtick or tilde.
- **sudo without a password**, handy for setting the VM up over SSH.

Terminal shows the progress. The first time, it downloads Ubuntu's desktop installer (about 6 GB, kept in `~/Library/Application Support/ParallelsManager/UbuntuInstall` and checked against Ubuntu's checksums). The install takes 15 to 40 minutes and ends with the VM turning itself off; then a snapshot of the fresh install is taken and the VM starts. Terminal prints its address and the SSH command; your Mac's SSH public keys are already in it, and it has your Mac's time zone.

It needs **Parallels Desktop Pro or Business** (creating VMs from the command line) and two Homebrew packages: `brew install xorriso openssl` (macOS's own `openssl` can't make the password hash Ubuntu needs).

The script, `Sources/ParallelsManager/Resources/install-ubuntu.sh`, also runs on its own: `VM_NAME="My Ubuntu" bash install-ubuntu.sh` asks for the password. Its header lists the other settings.

Two things learned the hard way, built into it:
- **Never snapshot a running Linux VM.** The pause trips Ubuntu's service watchdogs, which signs you out and stops Orca. Shut it down first.
- It uses Ubuntu's **desktop** installer, not the server one: only the desktop one brings Firefox and the other snap apps, and without a browser, sign-ins that open a web page fail.

## Building from Source

The easiest way is to double-click one of the Finder launchers in this folder.

### Finder Launchers

| File | What it does |
|---|---|
| `Build App.command` | Compiles the app and places it at `build/Parallels Manager.app`. Signs with your Developer ID. |
| `Package DMG.command` | Builds the app and creates a distributable DMG at `build/Parallels Manager 1.0.dmg`. |

Both launchers open in Terminal automatically when double-clicked. The first time you run them macOS may ask you to confirm — click Open.

### Terminal

```bash
cd parallels-manager

# Build the app (signed)
./build.sh

# Build without signing (for local testing)
./build.sh --skip-sign

# Build the full distributable DMG
./package-dmg.sh

# DMG without signing
./package-dmg.sh --skip-sign
```

Build output goes to `parallels-manager/build/`:

```
build/
  Parallels Manager.app      ← drag this to /Applications to use locally
  Parallels Manager 1.0.dmg  ← share this for distribution
```

## Project Structure

```
parallels-manager/
  Package.swift                   Swift Package Manager manifest
  Info.plist                      App bundle metadata (bundle ID, no sandbox)
  build.sh                        Build + sign script
  package-dmg.sh                  DMG packaging script
  Build App.command               Finder double-click launcher for build.sh
  Package DMG.command             Finder double-click launcher for package-dmg.sh
  Sources/ParallelsManager/
    ParallelsManagerApp.swift     App entry point, VM Actions CommandMenu
    VMModel.swift                 VM data model, VMStore, all state + actions
    PrlctlController.swift        prlctl subprocess wrapper + output parser
    ContentView.swift             Main window: List with selection, sheets, dialogs
    VMRow.swift                   Single VM row (VoiceOver-friendly single element)
    CloneSheet.swift              Sheet for entering a clone name
    NewWindowsVMSheet.swift       New Windows 11 ARM VM: launches install-windows-full.sh in Terminal
    NewUbuntuVMSheet.swift        New Ubuntu VM: launches install-ubuntu.sh in Terminal
    HardwareChoices.swift         Processors, memory and disk menus shared by both New VM dialogs
    Resources/install-ubuntu.sh   Unattended Ubuntu desktop install (download, answer file, prlctl)
```

## Technical Notes

- **No App Sandbox.** The app shells out to `/usr/local/bin/prlctl` which requires subprocess execution that the sandbox disallows. This means it cannot be distributed through the Mac App Store — distribute via DMG from your own website.
- **prlctl path.** Parallels installs `prlctl` at `/usr/local/bin/prlctl`. If yours is elsewhere, update the path in `PrlctlController.swift`.
- **Signing.** `build.sh` signs with `Developer ID Application: Kelly Ford (P887QF74N8)`. Update `SIGN_ID` in `build.sh` if you are building under a different certificate.
- **Swift Package Manager.** No Xcode project file — build entirely via `swift build`. macOS 13+ target.
- **Refresh.** `VMStore` re-runs `prlctl list --all` after each action and on ⌘R; there's no timer (taken out as a VoiceOver fix).

## Distribution

The `Package DMG.command` / `package-dmg.sh` produces a standard drag-to-Applications DMG suitable for posting on a website. Because the app is signed with a Developer ID certificate (not notarized), Gatekeeper will warn users when they first open it. They can right-click → Open to bypass the warning, or you can notarize the DMG with `xcrun notarytool` if you want a frictionless download experience.
