import SwiftUI

/// What this Mac can give a VM, and the choices offered for processors,
/// memory and disk in the New VM dialogs.
enum HostResources {
    static let cores = ProcessInfo.processInfo.activeProcessorCount
    static let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)

    /// Memory always left to the Mac itself, so a VM can't starve it.
    static let keptForMacGB = 4

    static var processorChoices: [Int] { Array(1...max(1, cores)) }

    static var memoryChoicesGB: [Int] {
        let most = max(2, memoryGB - keptForMacGB)
        return [2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128].filter { $0 <= most }
    }

    static let diskChoicesGB = [32, 64, 128, 256, 512]

    /// `wanted`, or the nearest choice at or below it that this Mac allows.
    static func clamp(_ wanted: Int, to choices: [Int]) -> Int {
        choices.last { $0 <= wanted } ?? choices.first ?? wanted
    }
}

/// Processors, memory and disk size: three pop-up menus, each named for
/// VoiceOver and reached with Tab like the fields above them.
struct HardwareChoices: View {
    @Binding var processors: Int
    @Binding var memoryGB: Int
    @Binding var diskGB: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("Processors:").gridColumnAlignment(.trailing)
                Picker("Processors", selection: $processors) {
                    ForEach(HostResources.processorChoices, id: \.self) { n in
                        Text(n == 1 ? "1 processor" : "\(n) processors").tag(n)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .help("This Mac has \(HostResources.cores).")
            }
            GridRow {
                Text("Memory:")
                Picker("Memory", selection: $memoryGB) {
                    ForEach(HostResources.memoryChoicesGB, id: \.self) { gb in
                        Text("\(gb) GB").tag(gb)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .help("This Mac has \(HostResources.memoryGB) GB; at least \(HostResources.keptForMacGB) GB is always left for it.")
            }
            GridRow {
                Text("Disk size:")
                Picker("Disk size", selection: $diskGB) {
                    ForEach(HostResources.diskChoicesGB, id: \.self) { gb in
                        Text("\(gb) GB").tag(gb)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .help("The most the VM's disk can grow to. It only takes up what's used.")
            }
        }
    }
}
