import XCTest
@testable import ShotStashCore

final class SaveNamerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-09-19 14:52:03 UTC
    private let date = Date(timeIntervalSince1970: 1_789_829_523)
    private let folder = URL(fileURLWithPath: "/tmp/dest", isDirectory: true)

    func testBaseNameMatchesAppleConvention() {
        XCTAssertEqual(SaveNamer.baseName(for: date, timeZone: utc), "Screenshot 2026-09-19 at 14.52.03")
    }

    func testDestinationWhenNoCollision() {
        let url = SaveNamer.destination(for: date, in: folder, timeZone: utc) { _ in false }
        XCTAssertEqual(url.path, "/tmp/dest/Screenshot 2026-09-19 at 14.52.03.png")
    }

    func testDestinationAppendsCounterOnCollision() {
        let taken: Set<String> = [
            "/tmp/dest/Screenshot 2026-09-19 at 14.52.03.png",
            "/tmp/dest/Screenshot 2026-09-19 at 14.52.03 (2).png",
        ]
        let url = SaveNamer.destination(for: date, in: folder, timeZone: utc) { taken.contains($0.path) }
        XCTAssertEqual(url.path, "/tmp/dest/Screenshot 2026-09-19 at 14.52.03 (3).png")
    }
}
