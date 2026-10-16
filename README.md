# Parallels Manager

A native macOS app to manage Parallels Desktop virtual machines, made to work fully with VoiceOver and the keyboard: start, stop, clone and delete VMs, and make new Windows 11 and Ubuntu VMs with no installer questions.

**[Download the latest release](https://github.com/TheIdeaPlace/ParallelsManager/releases/latest)** — `ParallelsManager-<version>.dmg`. Open it and move Parallels Manager to your Applications folder. It's signed and notarized by Apple, so it opens normally.

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
| macOS 14 Sonoma or later | On a Mac with Apple silicon |
| Parallels Desktop | `/usr/local/bin/prlctl` must be present |
| Parallels Desktop **Pro** or Business | Only for New Ubuntu VM and New Windows VM (creating VMs from the command line) |
| Homebrew packages | New Ubuntu VM: `brew install xorriso openssl`. New Windows VM: `brew install aria2 p7zip cabextract wimlib cdrtools` |
| Xcode | Only for building from source |

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

3. **Accessibility actions (VO + Command + Space)** — move VoiceOver focus to any VM row and press VO + Command + Space for its actions: Start, Stop, Pause, Resume, Clone, Delete, and Remove from List for an invalid VM.

Each VM row reads aloud as **"[Name], [status]"**, with "Busy" added while an action is running.

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
| `Package DMG.command` | Builds the app and creates a distributable DMG at `build/ParallelsManager-<version>.dmg`. |

Both launchers open in Terminal automatically when double-clicked. The first time you run them macOS may ask you to confirm — click Open.

### Terminal

```bash
# Run the tests
swift test

# Build the app (signed, for Apple silicon)
./build.sh

# Build without signing (for local testing)
./build.sh --skip-sign

# Build the DMG, signed
./package-dmg.sh

# ...and notarized and stapled, with the key in ~/.signing-kit
NOTARIZE=1 ./package-dmg.sh
```

Build output goes to `build/`:

```
build/
  Parallels Manager.app            ← move this to /Applications to use locally
  ParallelsManager-<version>.dmg   ← what a release publishes
```

## Project Structure

```
  Package.swift                   Swift Package Manager manifest (the app and its tests)
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
    Resources/install-windows-full.sh  Unattended Windows 11 ARM install
  Tests/ParallelsManagerTests/    Tests: reading prlctl's list, which actions each state allows, hardware limits
  release-notes/                  One file per release, used as its GitHub release notes
  .github/workflows/ci.yml        Tests, build and shellcheck on every push and pull request
  .github/workflows/release.yml   Signed, notarized release on a v* tag
```

## Technical Notes

- **No App Sandbox.** The app shells out to `/usr/local/bin/prlctl` which requires subprocess execution that the sandbox disallows. This means it cannot be distributed through the Mac App Store — distribute via DMG from your own website.
- **prlctl path.** Parallels installs `prlctl` at `/usr/local/bin/prlctl`. If yours is elsewhere, update the path in `PrlctlController.swift`.
- **Signing.** `build.sh` signs with `Developer ID Application: Kelly Ford (P887QF74N8)`. Update `SIGN_ID` in `build.sh` if you are building under a different certificate.
- **Swift Package Manager.** No Xcode project file — build entirely via `swift build`. macOS 14+ target.
- **Refresh.** `VMStore` re-runs `prlctl list --all` after each action and on ⌘R; there's no timer (taken out as a VoiceOver fix).

## Releasing

The version lives in one place, `CFBundleShortVersionString` in `Info.plist`. To release:

1. Bump it, and add `release-notes/v<version>.md` (written for people using the app).
2. Push the tag `v<version>`.

`.github/workflows/release.yml` then checks the tag matches `Info.plist` and the notes exist, runs the tests, builds, signs with Developer ID, notarizes and staples the DMG, and publishes the GitHub release with the DMG and its SHA-256 checksum.

Running the Release workflow by hand (Actions, Release, Run workflow) does all of that except publishing: a rehearsal, with the DMG kept as the run's artifact.

The signing secrets (`MACOS_CERTIFICATE_*`, `NOTARY_*`) are set by `signing/sync-secrets.py` in The-Idea-Place-Projects, never by hand.

## History

Parallels Manager lived in [TheWorkBench](https://github.com/TheIdeaPlace/TheWorkBench) (`parallels-manager/`) until 1.1.0; its commit history came with it.
