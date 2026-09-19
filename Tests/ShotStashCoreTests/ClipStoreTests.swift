import XCTest
@testable import ShotStashCore

final class ClipStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotstash-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFile(in store: ClipStore, bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47]) throws -> URL {
        let url = store.newFileURL()
        try Data(bytes).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testInitCreatesDirectory() throws {
        _ = try ClipStore(directory: dir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testMixedItemsNewestFirstAndLatestImage() throws {
        let store = try ClipStore(directory: dir)
        let image = try XCTUnwrap(store.addImage(fileURL: try makeFile(in: store), width: 10, height: 20))
        let text = try XCTUnwrap(store.addText("hello"))
        XCTAssertEqual(store.items, [text, image])
        XCTAssertEqual(store.latest, text)
        XCTAssertEqual(store.latestImage, image)
        XCTAssertEqual(image.sizeLabel, "10×20")
        XCTAssertNil(text.sizeLabel)
    }

    func testEvictsOldestBeyondCapacityAndDeletesItsFile() throws {
        let store = try ClipStore(directory: dir, capacity: 2)
        let first = try XCTUnwrap(store.addImage(fileURL: try makeFile(in: store, bytes: [1]), width: 1, height: 1))
        store.addText("two")
        store.addText("three")
        XCTAssertEqual(store.items.count, 2)
        XCTAssertFalse(store.items.contains(first))
        XCTAssertFalse(exists(first.fileURL!))
    }

    func testTextDedupAndBlankRejected() throws {
        let store = try ClipStore(directory: dir)
        XCTAssertNotNil(store.addText("same"))
        XCTAssertNil(store.addText("same"))
        XCTAssertNil(store.addText("   \n"))
        XCTAssertNotNil(store.addText("different"))
        XCTAssertNotNil(store.addText("same"))  // not the newest any more, so allowed
        XCTAssertEqual(store.items.count, 3)
    }

    func testImageDedupDeletesTheNewFile() throws {
        let store = try ClipStore(directory: dir)
        XCTAssertNotNil(store.addImage(fileURL: try makeFile(in: store, bytes: [7, 7]), width: 1, height: 1))
        let dup = try makeFile(in: store, bytes: [7, 7])
        XCTAssertNil(store.addImage(fileURL: dup, width: 1, height: 1))
        XCTAssertFalse(exists(dup))
        XCTAssertEqual(store.items.count, 1)
    }

    func testMoveToTop() throws {
        let store = try ClipStore(directory: dir)
        let a = try XCTUnwrap(store.addText("a"))
        let b = try XCTUnwrap(store.addText("b"))
        var changes = 0
        store.onChange = { changes += 1 }
        store.moveToTop(a)
        XCTAssertEqual(store.items, [a, b])
        store.moveToTop(a)  // already on top: no change event
        XCTAssertEqual(changes, 1)
    }

    func testRemoveDeletesFileAndFiresOnChange() throws {
        let store = try ClipStore(directory: dir)
        var changes = 0
        store.onChange = { changes += 1 }
        let c = try XCTUnwrap(store.addImage(fileURL: try makeFile(in: store), width: 1, height: 1))
        store.remove(c)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.latest)
        XCTAssertFalse(exists(c.fileURL!))
        XCTAssertEqual(changes, 2)
    }

    func testItemByID() throws {
        let store = try ClipStore(directory: dir)
        let c = try XCTUnwrap(store.addText("x"))
        XCTAssertEqual(store.item(id: c.id), c)
        XCTAssertNil(store.item(id: UUID()))
    }

    func testClearRemovesAllFiles() throws {
        let store = try ClipStore(directory: dir)
        let a = try XCTUnwrap(store.addImage(fileURL: try makeFile(in: store, bytes: [1]), width: 1, height: 1))
        let b = try XCTUnwrap(store.addImage(fileURL: try makeFile(in: store, bytes: [2]), width: 1, height: 1))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(exists(a.fileURL!))
        XCTAssertFalse(exists(b.fileURL!))
    }

    func testPurgeDirectoryDeletesStaleFiles() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = dir.appendingPathComponent("stale.png")
        try Data([1, 2, 3]).write(to: stale)
        let store = try ClipStore(directory: dir)
        store.purgeDirectory()
        XCTAssertFalse(exists(stale))
        XCTAssertTrue(store.items.isEmpty)
    }
}
