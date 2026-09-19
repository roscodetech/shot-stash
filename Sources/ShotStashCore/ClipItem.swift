import Foundation

/// One clipboard entry: an image held as a PNG file in the stash, or a piece of text.
public struct ClipItem: Identifiable, Equatable {
    public enum Content: Equatable {
        case image(fileURL: URL, width: Int, height: Int)
        case text(String)
    }

    public let id: UUID
    public let createdAt: Date
    public let content: Content

    public init(id: UUID = UUID(), createdAt: Date = Date(), content: Content) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
    }

    public var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    public var fileURL: URL? {
        if case let .image(url, _, _) = content { return url }
        return nil
    }

    public var text: String? {
        if case let .text(s) = content { return s }
        return nil
    }

    /// "1024×768" for images, nil for text.
    public var sizeLabel: String? {
        if case let .image(_, w, h) = content { return "\(w)×\(h)" }
        return nil
    }

    /// Single-line summary for menus and the picker.
    public var preview: String {
        switch content {
        case let .image(_, w, h): return "Image \(w)×\(h)"
        case let .text(s): return Self.preview(of: s)
        }
    }

    /// Collapses whitespace/newlines to single spaces and truncates with an ellipsis.
    public static func preview(of text: String, limit: Int = 60) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
