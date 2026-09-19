import Foundation
import ImageIO

enum CaptureMode {
    case selection
    case fullScreen
}

/// Drives Apple's /usr/sbin/screencapture so we get the native crosshair UI.
final class CaptureService {
    private var running: Process?

    /// Completion is called on the main queue with `true` when a file was produced.
    /// Esc during selection produces no file and reports `false`.
    func capture(mode: CaptureMode, to url: URL, completion: @escaping (Bool) -> Void) {
        guard running == nil else { return }  // ignore hotkey spam while a capture is up
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x", "-t", "png"]          // -x: no shutter sound
        if mode == .selection { args.insert("-i", at: 0) }  // -i: interactive; Space toggles window mode
        args.append(url.path)
        process.arguments = args
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.running = nil
                completion(FileManager.default.fileExists(atPath: url.path))
            }
        }
        do {
            try process.run()
            running = process
        } catch {
            NSLog("ShotStash: failed to launch screencapture: \(error)")
            completion(false)
        }
    }

    static func pixelSize(of url: URL) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return (0, 0) }
        return (w, h)
    }
}
