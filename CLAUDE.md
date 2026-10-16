# CLAUDE.md

Parallels Manager: a SwiftUI Mac app (Swift Package Manager, no Xcode project) that manages
Parallels Desktop VMs through `prlctl`, made to work fully with VoiceOver and the keyboard, and
makes new Windows 11 and Ubuntu VMs with unattended install scripts. Kelly uses it with VoiceOver,
so every change has to work by keyboard and be named for VoiceOver. The README is the user guide;
keep it in step with behaviour.

## Commands

```
swift test                     # the tests (what CI runs)
./build.sh [--skip-sign]       # build/Parallels Manager.app for Apple silicon, signed with Developer ID
./package-dmg.sh               # build/ParallelsManager-<version>.dmg, signed
NOTARIZE=1 ./package-dmg.sh    # ...notarized and stapled (key from ~/.signing-kit)
shellcheck -S warning build.sh package-dmg.sh Sources/ParallelsManager/Resources/*.sh
```

To try a build: quit the running copy first (an open sheet blocks Quit, so `pkill -x
ParallelsManager`), then open `build/Parallels Manager.app`.

## Layout

- `Sources/ParallelsManager/`: `VMModel.swift` (VMStore, VMStatus, VMAction), `PrlctlController.swift`
  (runs prlctl, parses `prlctl list`), `ContentView.swift`, `ParallelsManagerApp.swift` (menus),
  `NewUbuntuVMSheet.swift` / `NewWindowsVMSheet.swift` (launch the install scripts in Terminal),
  `HardwareChoices.swift` (processors, memory, disk menus).
- `Sources/ParallelsManager/Resources/install-ubuntu.sh`, `install-windows-full.sh`: the unattended
  installers. `build.sh` copies every `*.sh` / `*.command` there into the app's Resources.

## Rules learned the hard way

- **No `Form` in a sheet.** Opened from the File menu, a `Form` in a sheet left Tab stuck in the
  first field (or typing a tab into it). Use `Grid` rows with a `Text` label and a
  `.labelsHidden()` control.
- **Don't add `.accessibilityLabel` to a control that already has a label** (`Picker("Memory", ...)`):
  VoiceOver then hears the name twice. A `TextField` whose label is hidden does need one.
- **No refreshing on a timer.** The list's auto-refresh was removed as a VoiceOver fix; refresh
  after actions and on ⌘R only.
- **SwiftUI's New Window takes ⌘N** unless `CommandGroup(replacing: .newItem)` replaces it.
- **Never snapshot a running Linux VM** (the pause trips systemd's watchdogs: the user is signed
  out and Orca stops). The Ubuntu installer snapshots with the VM off.
- **Ubuntu's desktop installer, not the server one**: only it brings Firefox and the other snaps.
  Don't disable cloud-init in a new VM: it applies the SSH keys and time zone at first boot.
- **Test the dialogs by script before handing over**: System Events can open a sheet from the
  menu or by shortcut, press Tab, and read `AXFocusedUIElement` (role, description, value). Check
  both ways of opening.

## Releasing

The version is `CFBundleShortVersionString` in `Info.plist`, and nowhere else. Bump it, add
`release-notes/v<version>.md` in the same commit, then push the tag `v<version>`. The Release
workflow checks both, runs the tests, builds, signs, notarizes, staples and publishes the DMG and
its checksum. Run it by hand first for a rehearsal (no release, the DMG as an artifact).

Release notes are for users: what they'll notice, with the menu path and the key; an intro, then
**Added**, **Changed**, **Fixed**, then **Reporting Issues**, **Downloads**, **Requirements** and the
independence line.

Signing secrets come from `~/Documents/GitHub/The-Idea-Place-Projects/signing` (`repos.json`,
`sync-secrets.py`), never by hand. Commit messages are one plain-English sentence about the
user-visible change, with issue numbers.
