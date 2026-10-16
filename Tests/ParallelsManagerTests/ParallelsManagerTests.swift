import XCTest
@testable import ParallelsManager

final class ListParsingTests: XCTestCase {

    /// What `prlctl list --all -o uuid,status,name` prints: a header, then one
    /// line per VM, names with spaces included.
    private let sample = """
        UUID                                    STATUS       NAME
        {7647b252-f62c-464e-b9be-bad762d33f28}  running      TCP Linux
        {016eef15-f05f-4a6d-afb5-c7ed56d73d66}  stopped      TCP Linux Orca Latest
        {36326235-2ac4-44bc-85a7-b143475d0e20}  suspended    Windows 11 ARM
        {11111111-2222-3333-4444-555555555555}  paused       Paused One
        {c73dc491-6a3b-4e23-9751-8c2131eb8056}  invalid      TCP-Codex-Test
        {99999999-8888-7777-6666-555555555555}  migrating    Something New
        """

    func testEveryLineBecomesAVMWithItsWholeName() {
        let vms = PrlctlController.parseList(sample)
        XCTAssertEqual(vms.map(\.name), ["TCP Linux", "TCP Linux Orca Latest", "Windows 11 ARM",
                                         "Paused One", "TCP-Codex-Test", "Something New"])
        XCTAssertEqual(vms.first?.id, "{7647b252-f62c-464e-b9be-bad762d33f28}")
    }

    func testStatuses() {
        let statuses = PrlctlController.parseList(sample).map(\.status)
        XCTAssertEqual(statuses, [.running, .stopped, .suspended, .paused, .invalid, .unknown])
    }

    func testTheHeaderAndBlankLinesAreSkipped() {
        XCTAssertTrue(PrlctlController.parseList("UUID  STATUS  NAME\n\n").isEmpty)
    }
}

final class ActionTests: XCTestCase {

    /// A VM whose files are gone can only be removed from the list: Parallels
    /// can't start, clone or delete it without its files.
    func testAnInvalidVMCanOnlyBeRemovedFromTheList() {
        let s = VMStatus.invalid
        XCTAssertTrue(s.canUnregister)
        XCTAssertFalse(s.canDelete)
        XCTAssertFalse(s.canClone)
        XCTAssertFalse(s.canStart)
        XCTAssertEqual(s.displayName, "Invalid (files missing)")
    }

    func testOrdinaryVMsAreNeverOfferedRemoveFromList() {
        for s in [VMStatus.running, .stopped, .paused, .suspended, .unknown] {
            XCTAssertFalse(s.canUnregister, "\(s)")
            XCTAssertTrue(s.canDelete, "\(s)")
        }
    }

    func testRemoveFromListIsPrlctlUnregister() {
        XCTAssertEqual(VMAction.unregister.prlctlArgs, ["unregister"])
        XCTAssertEqual(VMAction.unregister.displayName, "Remove from List")
    }
}

final class HardwareChoiceTests: XCTestCase {

    func testMemoryAlwaysLeavesTheMacItsShare() {
        let most = HostResources.memoryChoicesGB.max() ?? 0
        XCTAssertGreaterThanOrEqual(most, 2)
        if HostResources.memoryGB > HostResources.keptForMacGB + 2 {
            XCTAssertLessThanOrEqual(most, HostResources.memoryGB - HostResources.keptForMacGB)
        }
    }

    func testProcessorsRunFromOneToThisMacsCount() {
        XCTAssertEqual(HostResources.processorChoices.first, 1)
        XCTAssertEqual(HostResources.processorChoices.last, max(1, HostResources.cores))
    }

    func testClampPicksTheNearestChoiceAtOrBelow() {
        let choices = [2, 4, 6, 8, 12]
        XCTAssertEqual(HostResources.clamp(8, to: choices), 8)
        XCTAssertEqual(HostResources.clamp(10, to: choices), 8)
        XCTAssertEqual(HostResources.clamp(64, to: choices), 12)
        XCTAssertEqual(HostResources.clamp(1, to: choices), 2)  // below every choice: the smallest
    }

    func testDiskChoicesFitUbuntusDesktop() {
        // The Ubuntu installer refuses less than about 25 GB.
        XCTAssertGreaterThanOrEqual(HostResources.diskChoicesGB.min() ?? 0, 32)
    }
}
