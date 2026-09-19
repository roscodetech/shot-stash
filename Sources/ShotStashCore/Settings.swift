import Foundation

/// UserDefaults-backed preferences. Captures themselves are never persisted.
public final class Settings {
    public static let suiteName = "com.roscodetech.shotstash"

    private enum Key {
        static let defaultFolder = "defaultFolder"
        static let hotkeySelection = "hotkeySelection"
        static let hotkeyFullScreen = "hotkeyFullScreen"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static var desktopURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    public var defaultFolder: URL {
        get {
            if let path = defaults.string(forKey: Key.defaultFolder) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return Self.desktopURL
        }
        set { defaults.set(newValue.path, forKey: Key.defaultFolder) }
    }

    public var defaultFolderName: String { defaultFolder.lastPathComponent }

    public func resetDefaultFolder() {
        defaults.removeObject(forKey: Key.defaultFolder)
    }

    public var hotkeySelection: Hotkey {
        get { hotkey(forKey: Key.hotkeySelection) ?? .defaultSelection }
        set { set(hotkey: newValue, forKey: Key.hotkeySelection) }
    }

    public var hotkeyFullScreen: Hotkey {
        get { hotkey(forKey: Key.hotkeyFullScreen) ?? .defaultFullScreen }
        set { set(hotkey: newValue, forKey: Key.hotkeyFullScreen) }
    }

    private func hotkey(forKey key: String) -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private func set(hotkey: Hotkey, forKey key: String) {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: key)
        }
    }
}
