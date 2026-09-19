import Foundation

/// Holds the most recent clipboard items (newest first) and owns their temp files.
public final class ClipStore {
    public let directory: URL
    public let capacity: Int
    public private(set) var items: [ClipItem] = []
    /// Called after every mutation. Used by the menu and panel to refresh.
    public var onChange: (() -> Void)?

    private let fileManager = FileManager.default

    public init(directory: URL, capacity: Int = 10) throws {
        self.directory = directory
        self.capacity = capacity
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var latest: ClipItem? { items.first }
    public var latestImage: ClipItem? { items.first { $0.isImage } }

    /// A fresh, unique PNG path inside the stash directory.
    public func newFileURL() -> URL {
        directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    }

    /// Adds an image already written to `fileURL`. Returns nil (and deletes `fileURL`)
    /// when its bytes equal the newest item's image.
    @discardableResult
    public func addImage(fileURL: URL, width: Int, height: Int, createdAt: Date = Date()) -> ClipItem? {
        if let latest, let latestURL = latest.fileURL,
           let a = try? Data(contentsOf: latestURL), let b = try? Data(contentsOf: fileURL), a == b {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return insert(ClipItem(createdAt: createdAt, content: .image(fileURL: fileURL, width: width, height: height)))
    }

    /// Adds text. Returns nil for empty/whitespace-only text or an exact duplicate of the newest item.
    @discardableResult
    public func addText(_ text: String, createdAt: Date = Date()) -> ClipItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let latest, latest.text == text { return nil }
        return insert(ClipItem(createdAt: createdAt, content: .text(text)))
    }

    /// Re-copying an item promotes it to newest.
    public func moveToTop(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index != 0 else { return }
        items.remove(at: index)
        items.insert(item, at: 0)
        onChange?()
    }

    public func item(id: UUID) -> ClipItem? {
        items.first { $0.id == id }
    }

    public func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        deleteFile(of: item)
        onChange?()
    }

    public func clear() {
        for item in items { deleteFile(of: item) }
        items.removeAll()
        onChange?()
    }

    /// Deletes every file in the stash directory (leftovers from a crash) and empties the list.
    public func purgeDirectory() {
        if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files { try? fileManager.removeItem(at: file) }
        }
        items.removeAll()
        onChange?()
    }

    // MARK: - Private

    private func insert(_ item: ClipItem) -> ClipItem {
        items.insert(item, at: 0)
        while items.count > capacity {
            deleteFile(of: items.removeLast())
        }
        onChange?()
        return item
    }

    private func deleteFile(of item: ClipItem) {
        if let url = item.fileURL { try? fileManager.removeItem(at: url) }
    }
}
