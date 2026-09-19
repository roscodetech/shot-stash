import XCTest
@testable import ShotStashCore

final class CaptureStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotstash-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFile(in store: CaptureStore) throws -> URL {
        let url = store.newFileURL()
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    func testInitCreatesDirectory() throws {
        _ = try CaptureStore(directory: dir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testAddPutsNewestFirstAndSetsLatest() throws {
        let store = try CaptureStore(directory: dir)
        let a = store.add(fileURL: try makeFile(in: store), width: 10, height: 20)
        let b = store.add(fileURL: try makeFile(in: store), width: 30, height: 40)
        XCTAssertEqual(store.captures, [b, a])
        XCTAssertEqual(store.latest, b)
        XCTAssertEqual(b.sizeLabel, "30×40")
    }

    func testEvictsOldestBeyondCapacityAndDeletesItsFile() throws {
        let store = try CaptureStore(directory: dir, capacity: 2)
        let first = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        _ = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        _ = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        XCTAssertEqual(store.captures.count, 2)
        XCTAssertFalse(store.captures.contains(first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
    }

    func testRemoveDeletesFileAndFiresOnChange() throws {
        let store = try CaptureStore(directory: dir)
        var changes = 0
        store.onChange = { changes += 1 }
        let c = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        store.remove(c)
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertNil(store.latest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.fileURL.path))
        XCTAssertEqual(changes, 2)
    }

    func testCaptureByID() throws {
        let store = try CaptureStore(directory: dir)
        let c = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        XCTAssertEqual(store.capture(id: c.id), c)
        XCTAssertNil(store.capture(id: UUID()))
    }

    func testClearRemovesAllFiles() throws {
        let store = try CaptureStore(directory: dir)
        let a = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        let b = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        store.clear()
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.fileURL.path))
    }

    func testPurgeDirectoryDeletesStaleFiles() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = dir.appendingPathComponent("stale.png")
        try Data([1, 2, 3]).write(to: stale)
        let store = try CaptureStore(directory: dir)
        store.purgeDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(store.captures.isEmpty)
    }
}
