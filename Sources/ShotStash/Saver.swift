import Foundation
import ShotStashCore

enum Saver {
    /// Copies the stashed PNG into `folder` with an Apple-style name. The stash keeps its copy.
    @discardableResult
    static func save(_ capture: Capture, to folder: URL) throws -> URL {
        let fm = FileManager.default
        let destination = SaveNamer.destination(for: capture.createdAt, in: folder) { fm.fileExists(atPath: $0.path) }
        try fm.copyItem(at: capture.fileURL, to: destination)
        return destination
    }
}
