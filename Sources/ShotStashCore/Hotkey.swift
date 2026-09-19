import Foundation

/// A global hotkey expressed with Carbon virtual key codes and modifier bits.
public struct Hotkey: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Carbon modifier masks (Events.h): cmdKey, shiftKey, optionKey, controlKey.
    public static let cmd: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// ⌃⌘4
    public static let defaultSelection = Hotkey(keyCode: 21, modifiers: control | cmd)
    /// ⌃⌘3
    public static let defaultFullScreen = Hotkey(keyCode: 20, modifiers: control | cmd)

    public var hasCommand: Bool { modifiers & Self.cmd != 0 }
    public var hasShift: Bool { modifiers & Self.shift != 0 }
    public var hasOption: Bool { modifiers & Self.option != 0 }
    public var hasControl: Bool { modifiers & Self.control != 0 }

    /// Printable key for the ANSI layout. Only the keys we expect people to bind.
    private static let keyLabels: [UInt32: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z", 49: "Space",
    ]

    public var keyLabel: String {
        Self.keyLabels[keyCode] ?? "key\(keyCode)"
    }

    /// Symbols in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    public var displayString: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption { s += "⌥" }
        if hasShift { s += "⇧" }
        if hasCommand { s += "⌘" }
        return s + keyLabel
    }
}
