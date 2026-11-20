import XCTest
@testable import Amp

final class AppRebrandTests: XCTestCase {
    func testLegacyDataIsCopiedWithoutDeletingTheOriginalOrReplacingNewData() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = parent.appendingPathComponent("Erhu")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let original = Data("database-and-playlists".utf8)
        try original.write(to: legacy.appendingPathComponent("library.sqlite"))
        let destination = LibraryPaths.migratedDirectory(in: parent)
        XCTAssertEqual(destination.lastPathComponent, "amp")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("library.sqlite")), original)
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("library.sqlite")), original)
        let newer = Data("new playlists".utf8)
        try newer.write(to: destination.appendingPathComponent("library.sqlite"))
        XCTAssertEqual(LibraryPaths.migratedDirectory(in: parent), destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("library.sqlite")), newer)
    }

    func testFailedMigrationKeepsUsingTheCompleteLegacyFolder() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = parent.appendingPathComponent("Erhu")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data("keep me".utf8).write(to: legacy.appendingPathComponent("library.sqlite"))
        let destination = LibraryPaths.migratedDirectory(in: parent, manager: FailingCopyManager())
        XCTAssertEqual(destination, legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("amp").path))
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("library.sqlite")), Data("keep me".utf8))
    }

    func testWidgetTransportDoesNotRequestForegroundLaunch() {
        XCTAssertFalse(AmpPlaybackIntent.openAppWhenRun)
        XCTAssertEqual(AmpPlaybackIntent(command: .next).command, .next)
    }
}
private final class FailingCopyManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
