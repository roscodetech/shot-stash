import AppKit
import ShotStashCore

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let store: CaptureStore

    var onCaptureSelection: (() -> Void)?
    var onCaptureFullScreen: (() -> Void)?
    var onSaveLastToDefault: (() -> Void)?
    var onQuit: (() -> Void)?

    /// Set to false by AppDelegate when Carbon refused a hotkey; the menu shows "(unavailable)".
    var selectionHotkeyAvailable = true
    var fullScreenHotkeyAvailable = true

    init(settings: Settings, store: CaptureStore) {
        self.settings = settings
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShotStash")
        }
    }

    func rebuild() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(hotkeyItem("Capture Selection", hotkey: settings.hotkeySelection,
                                available: selectionHotkeyAvailable) { [weak self] in self?.onCaptureSelection?() })
        menu.addItem(hotkeyItem("Capture Full Screen", hotkey: settings.hotkeyFullScreen,
                                available: fullScreenHotkeyAvailable) { [weak self] in self?.onCaptureFullScreen?() })
        menu.addItem(.separator())

        let hasCapture = store.latest != nil
        menu.addItem(item("Save Last to \(settings.defaultFolderName)", enabled: hasCapture) { [weak self] in
            self?.onSaveLastToDefault?()
        })
        menu.addItem(.separator())

        menu.addItem(item("Quit ShotStash", key: "q") { [weak self] in self?.onQuit?() })
        statusItem.menu = menu
    }

    // MARK: - Helpers

    private func hotkeyItem(_ title: String, hotkey: Hotkey, available: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let menuItem = item(available ? title : "\(title) (hotkey unavailable)", action: action)
        // Show the shortcut in the menu without letting AppKit intercept it (Carbon owns the global key).
        menuItem.keyEquivalent = hotkey.keyLabel.count == 1 ? hotkey.keyLabel.lowercased() : ""
        menuItem.keyEquivalentModifierMask = Self.menuFlags(for: hotkey)
        return menuItem
    }

    static func menuFlags(for hotkey: Hotkey) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if hotkey.hasCommand { flags.insert(.command) }
        if hotkey.hasShift { flags.insert(.shift) }
        if hotkey.hasOption { flags.insert(.option) }
        if hotkey.hasControl { flags.insert(.control) }
        return flags
    }

    /// Closure-backed NSMenuItem. The closure is retained via representedObject.
    func item(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command],
              enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = self
        menuItem.representedObject = ActionBox(action)
        menuItem.isEnabled = enabled
        return menuItem
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }
}

final class ActionBox {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}
