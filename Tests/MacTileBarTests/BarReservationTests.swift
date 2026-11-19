import Foundation
import XCTest
@testable import MacTileBar

final class BarReservationTests: XCTestCase {
    private func sandbox() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("external-bar.json")
    }

    func testRestoresOriginalAfterRelaunchAndPreservesBottom() throws {
        let journal = try sandbox()
        let original = ExternalBar(mode: .all, top: 8, bottom: 12)
        var current = original
        let firstRun = BarReservation(journal: journal)
        XCTAssertTrue(try firstRun.update(current: current, socket: "A", height: 32, reapply: true) { current = $0 })
        XCTAssertEqual(current.description, "all:32:12")

        let relaunched = BarReservation(journal: journal)
        XCTAssertTrue(try relaunched.update(current: current, socket: "A", height: 32, reapply: true) { _ in
            XCTFail("An adequate reservation should be reused")
        })
        try relaunched.release(socket: "A", read: { current }) { current = $0 }
        XCTAssertEqual(current, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testExternalChangesArePreservedAndSuspendWrites() throws {
        let journal = try sandbox()
        let reservation = BarReservation(journal: journal)
        var current = ExternalBar(mode: .off, top: 0, bottom: 0)
        XCTAssertTrue(try reservation.update(current: current, socket: "A", height: 32, reapply: true) { current = $0 })

        current = ExternalBar(mode: .main, top: 10, bottom: 5)
        XCTAssertFalse(try reservation.update(current: current, socket: "A", height: 32, reapply: false) { _ in
            XCTFail("The other client's configuration should be left alone")
        })
        try reservation.release(socket: "A", read: { current }) { _ in XCTFail("No longer owned") }
        XCTAssertEqual(current.description, "main:10:5")
    }

    func testCleanupChecksLiveValueBeforeWriting() throws {
        let reservation = BarReservation(journal: try sandbox())
        var current = ExternalBar(mode: .off, top: 0, bottom: 0)
        XCTAssertTrue(try reservation.update(current: current, socket: "A", height: 32, reapply: true) { current = $0 })

        // This change has not yet been observed by the polling loop.
        current = ExternalBar(mode: .all, top: 48, bottom: 9)
        try reservation.release(socket: "A", read: { current }) { _ in XCTFail("No longer owned") }
        XCTAssertEqual(current.description, "all:48:9")
    }

    func testNewYabaiInstanceDoesNotInheritOldOwnership() throws {
        let reservation = BarReservation(journal: try sandbox())
        var current = ExternalBar(mode: .off, top: 0, bottom: 0)
        XCTAssertTrue(try reservation.update(current: current, socket: "A", height: 32, reapply: true) { current = $0 })

        // The restarted server happens to set the same value itself.
        XCTAssertTrue(try reservation.update(current: current, socket: "B", height: 32, reapply: true) { _ in
            XCTFail("The new server already reserves enough")
        })
        try reservation.release(socket: "B", read: { current }) { _ in XCTFail("The new server owns this value") }
        XCTAssertEqual(current.description, "all:32:0")
    }

    func testInterruptedResizeCanRestoreFromPreviouslyAppliedValue() throws {
        struct Interrupted: Error {}
        let reservation = BarReservation(journal: try sandbox())
        let original = ExternalBar(mode: .off, top: 0, bottom: 0)
        var current = original
        XCTAssertTrue(try reservation.update(current: current, socket: "A", height: 32, reapply: true) { current = $0 })
        XCTAssertThrowsError(try reservation.update(current: current, socket: "A", height: 48, reapply: true) { _ in
            throw Interrupted()
        })

        try reservation.release(socket: "A", read: { current }) { current = $0 }
        XCTAssertEqual(current, original)
    }
}
