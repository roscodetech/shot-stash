import Foundation

/// One screenshot held in the temporary stash.
public struct Capture: Identifiable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let createdAt: Date
    public let width: Int
    public let height: Int

    public init(id: UUID = UUID(), fileURL: URL, createdAt: Date = Date(), width: Int, height: Int) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.width = width
        self.height = height
    }

    /// e.g. "1024×768"
    public var sizeLabel: String { "\(width)×\(height)" }
}
