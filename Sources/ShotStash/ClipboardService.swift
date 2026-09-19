import AppKit
import ShotStashCore

enum ClipboardService {
    /// Change count of the last write we made, so the watcher can ignore our own writes.
    private(set) static var lastWrittenChangeCount = -1

    /// Writes the item back to the general pasteboard. Images get PNG + TIFF so every app can paste.
    @discardableResult
    static func copy(_ item: ClipItem) -> Bool {
        let pasteboard = NSPasteboard.general
        switch item.content {
        case let .image(url, _, _):
            guard let png = try? Data(contentsOf: url),
                  let image = NSImage(data: png),
                  let tiff = image.tiffRepresentation
            else { return false }
            pasteboard.clearContents()
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(png, forType: .png)
            pasteboard.setData(tiff, forType: .tiff)
        case let .text(text):
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        lastWrittenChangeCount = pasteboard.changeCount
        return true
    }
}
