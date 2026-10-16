import SwiftUI
import AppKit

/// Makes a new Ubuntu desktop VM with no installer questions: collects a few
/// choices, then runs the bundled install-ubuntu.sh in Terminal, where its
/// progress can be read (the install takes 15 to 40 minutes).
struct NewUbuntuVMSheet: View {
    @EnvironmentObject private var store: VMStore
    @Environment(\.dismiss) private var dismiss

    @State private var vmName = "Ubuntu"
    @State private var userName = NSUserName().lowercased()
    @State private var password = ""
    @State private var orca = true
    @State private var autoLogin = true
    @State private var orcaKeyGrave = true
    @State private var noPasswordSudo = false
    // Up to 4 processors and 6 GB (4 GB on a Mac with less than 16 GB), and
    // a 64 GB disk: plenty for a desktop, and two can run at once.
    @State private var processors = HostResources.clamp(min(4, max(2, HostResources.cores / 2)),
                                                        to: HostResources.processorChoices)
    @State private var memoryGB = HostResources.clamp(HostResources.memoryGB >= 16 ? 6 : 4,
                                                      to: HostResources.memoryChoicesGB)
    @State private var diskGB = 64
    @State private var errorMessage: String? = nil

    /// Ubuntu's rule for user names: lower case, starting with a letter.
    private var userNameIsValid: Bool {
        userName.range(of: "^[a-z][a-z0-9_-]{0,31}$", options: .regularExpression) != nil
    }

    private var canCreate: Bool {
        !vmName.trimmingCharacters(in: .whitespaces).isEmpty && userNameIsValid && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Ubuntu VM")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // A Grid, not a Form: in this sheet a Form left Tab stuck in the
            // first field (or typing a tab into it), and its checkboxes had no
            // names for VoiceOver.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("VM name:").gridColumnAlignment(.trailing)
                    TextField("VM name", text: $vmName)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("VM name")
                }
                GridRow {
                    Text("Ubuntu user name:")
                    TextField("Ubuntu user name", text: $userName)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("Ubuntu user name")
                }
                GridRow {
                    Text("Password:")
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("Ubuntu password")
                }
            }
            .frame(width: 440)

            HardwareChoices(processors: $processors, memoryGB: $memoryGB, diskGB: $diskGB)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Orca screen reader on from the start", isOn: $orca)
                Toggle("Sign in automatically", isOn: $autoLogin)
                Toggle("Backtick key is Caps Lock, Orca's key (laptop layout)", isOn: $orcaKeyGrave)
                    .help("macOS keeps the real Caps Lock for itself, so the backtick/tilde key takes its place in Ubuntu, as SharpKeys does on Windows.")
                Toggle("sudo without a password", isOn: $noPasswordSudo)
                    .help("Handy for setting the VM up over SSH. Leave it off for a VM others can reach.")
            }
            .toggleStyle(.checkbox)

            if !userName.isEmpty && !userNameIsValid {
                Text("A user name needs lower-case letters, digits, - or _, and must start with a letter.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("Downloads Ubuntu 26.04 LTS's desktop installer (about 6 GB the first time, kept after that) and installs it with no questions: the full desktop with Firefox, an SSH server with your Mac's SSH keys, and your Mac's time zone. Terminal shows the progress; press ⌘R to see the new VM in the list. The install takes 15 to 40 minutes, then a snapshot of the fresh install is taken and the VM starts.\n\nNeeds Parallels Desktop Pro and two Homebrew packages: brew install xorriso openssl")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create VM") { launch() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 500)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Ubuntu VM dialog")
    }

    // MARK: - Launch

    private func launch() {
        errorMessage = nil

        guard let shURL = Bundle.main.url(forResource: "install-ubuntu", withExtension: "sh") else {
            errorMessage = "install-ubuntu.sh not found in app bundle."
            return
        }

        let fm = FileManager.default
        let workDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ParallelsManager/UbuntuInstall")
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("ParallelsManagerUbuntu-\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

            let tmpSh = tmpDir.appendingPathComponent("install-ubuntu.sh")
            try fm.copyItem(at: shURL, to: tmpSh)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpSh.path)

            // The password goes in a file only this user can read, which the
            // script deletes as soon as it has read it, rather than in the
            // launcher's text.
            let passwordFile = tmpDir.appendingPathComponent("password")
            fm.createFile(atPath: passwordFile.path, contents: Data(password.utf8),
                          attributes: [.posixPermissions: 0o600])

            func quoted(_ s: String) -> String {
                "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }
            let flag = { (on: Bool) in on ? "1" : "0" }

            let script = [
                "#!/usr/bin/env bash",
                "export VM_NAME=\(quoted(vmName.trimmingCharacters(in: .whitespaces)))",
                "export VM_USER=\(quoted(userName))",
                "export VM_PASSWORD_FILE=\(quoted(passwordFile.path))",
                "export WORK_DIR=\(quoted(workDir.path))",
                "export ORCA=\(flag(orca))",
                "export AUTOLOGIN=\(flag(autoLogin))",
                "export ORCA_KEY_GRAVE=\(flag(orcaKeyGrave))",
                "export NOPASSWD_SUDO=\(flag(noPasswordSudo))",
                "export VM_CPUS=\(processors)",
                "export VM_RAM=\(memoryGB * 1024)",
                "export VM_DISK_GB=\(diskGB)",
                "export PATH=\"/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH\"",
                "cd \"$(dirname \"$0\")\"",
                "bash install-ubuntu.sh",
                "status=$?",
                "rm -f \(quoted(passwordFile.path))",
                "echo \"  \"",
                "echo \"Done. Press Return to close.\"",
                "read -r",
                "exit $status"
            ].joined(separator: "\n")

            let wrapperURL = tmpDir.appendingPathComponent("install-ubuntu.command")
            try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapperURL.path)

            NSWorkspace.shared.open(wrapperURL)
        } catch {
            errorMessage = "Setup error: \(error.localizedDescription)"
            return
        }

        // No refreshing on a timer to catch the new VM (the list's timer was
        // taken out as a VoiceOver fix): Terminal says when it's created, and
        // ⌘R then shows it.
        password = ""
        dismiss()
    }
}
