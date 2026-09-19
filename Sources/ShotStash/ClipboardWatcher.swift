import AppKit
import ShotStashCore

/// Polls the general pasteboard and records new text and images into the store.
/// macOS offers no clipboard-change notification, so polling the change count is the standard approach.
final class ClipboardWatcher {
    private let store: ClipStore
    private var timer: Timer?
    private var lastChangeCount: Int

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init(store: ClipStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start(interval: TimeInterval = 0.5) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ClipboardService.lastWrittenChangeCount else { return }  // our own write

        let types = pasteboard.types ?? []
        if types.contains(Self.concealed) || types.contains(Self.transient) { return }

        if let png = imagePNG(from: pasteboard) {
            let url = store.newFileURL()
            do {
                try png.write(to: url)
            } catch {
                NSLog("ShotStash: could not stash clipboard image: \(error)")
                return
            }
            let size = CaptureService.pixelSize(of: url)
            store.addImage(fileURL: url, width: size.width, height: size.height)
        } else if let text = pasteboard.string(forType: .string) {
            store.addText(text)
        }
    }

    /// PNG bytes for an image on the pasteboard, converting from TIFF when needed.
    private func imagePNG(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
