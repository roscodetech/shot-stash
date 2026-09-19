import XCTest
@testable import ShotStashCore

final class ClipItemTests: XCTestCase {
    func testPreviewCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual(ClipItem.preview(of: "  hello\n\n  world\tagain "), "hello world again")
        let long = String(repeating: "abcde ", count: 20)
        let preview = ClipItem.preview(of: long, limit: 12)
        XCTAssertEqual(preview, "abcde abcde…")
    }

    func testPreviewForImageAndText() {
        let image = ClipItem(content: .image(fileURL: URL(fileURLWithPath: "/tmp/x.png"), width: 3, height: 4))
        XCTAssertEqual(image.preview, "Image 3×4")
        XCTAssertTrue(image.isImage)
        let text = ClipItem(content: .text("plain"))
        XCTAssertEqual(text.preview, "plain")
        XCTAssertEqual(text.text, "plain")
        XCTAssertNil(text.fileURL)
    }
}
