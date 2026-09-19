import Foundation

/// Holds the most recent captures (newest first) and owns their temp files.
public final class CaptureStore {
    public let directory: URL
    public let capacity: Int
    public private(set) var captures: [Capture] = []
    /// Called after every mutation. Used by the menu to rebuild itself.
    public var onChange: (() -> Void)?

    private let fileManager = FileManager.default

    public init(directory: URL, capacity: Int = 10) throws {
        self.directory = directory
        self.capacity = capacity
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var latest: Capture? { captures.first }

    /// A fresh, unique PNG path inside the stash directory.
    public func newFileURL() -> URL {
        directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    }

    @discardableResult
    public func add(fileURL: URL, width: Int, height: Int, createdAt: Date = Date()) -> Capture {
        let capture = Capture(fileURL: fileURL, createdAt: createdAt, width: width, height: height)
        captures.insert(capture, at: 0)
        while captures.count > capacity {
            let evicted = captures.removeLast()
            try? fileManager.removeItem(at: evicted.fileURL)
        }
        onChange?()
        return capture
    }

    public func capture(id: UUID) -> Capture? {
        captures.first { $0.id == id }
    }

    public func remove(_ capture: Capture) {
        captures.removeAll { $0.id == capture.id }
        try? fileManager.removeItem(at: capture.fileURL)
        onChange?()
    }

    public func clear() {
        for capture in captures {
            try? fileManager.removeItem(at: capture.fileURL)
        }
        captures.removeAll()
        onChange?()
    }

    /// Deletes every file in the stash directory (leftovers from a crash) and empties the list.
    public func purgeDirectory() {
        if let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for item in items {
                try? fileManager.removeItem(at: item)
            }
        }
        captures.removeAll()
        onChange?()
    }
}
