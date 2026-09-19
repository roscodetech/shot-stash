import AppKit
import ShotStashCore

enum ClipboardService {
    /// Writes PNG and TIFF flavors so every app (Finder, browsers, terminals, Claude Code) can paste.
    @discardableResult
    static func copy(_ capture: Capture) -> Bool {
        guard let png = try? Data(contentsOf: capture.fileURL),
              let image = NSImage(data: png),
              let tiff = image.tiffRepresentation
        else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(tiff, forType: .tiff)
        return true
    }
}
