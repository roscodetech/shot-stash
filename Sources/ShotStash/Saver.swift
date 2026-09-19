import Foundation
import ShotStashCore

enum Saver {
    enum SaveError: LocalizedError {
        case notAnImage
        var errorDescription: String? { "Only images can be saved as files." }
    }

    /// Copies a stashed image into `folder` with an Apple-style name. The stash keeps its copy.
    @discardableResult
    static func save(_ item: ClipItem, to folder: URL) throws -> URL {
        guard let source = item.fileURL else { throw SaveError.notAnImage }
        let fm = FileManager.default
        let destination = SaveNamer.destination(for: item.createdAt, in: folder) { fm.fileExists(atPath: $0.path) }
        try fm.copyItem(at: source, to: destination)
        return destination
    }
}
