import AppKit
import ShotStashCore

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let store: CaptureStore

    var onCaptureSelection: (() -> Void)?
    var onCaptureFullScreen: (() -> Void)?
    var onSaveLastToDefault: (() -> Void)?
    var onSaveLastToFolder: (() -> Void)?
    var onCopy: ((Capture) -> Void)?
    var onSaveToDefault: ((Capture) -> Void)?
    var onSaveToFolder: ((Capture) -> Void)?
    var onDelete: ((Capture) -> Void)?
    var onClearAll: (() -> Void)?
    var onChangeDefaultFolder: (() -> Void)?
    var onResetDefaultFolder: (() -> Void)?
    var launchAtLoginEnabled: () -> Bool = { false }
    var onToggleLaunchAtLogin: (() -> Void)?
    var onQuit: (() -> Void)?

    /// Set to false by AppDelegate when Carbon refused a hotkey; the menu shows "(unavailable)".
    var selectionHotkeyAvailable = true
    var fullScreenHotkeyAvailable = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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
        menu.addItem(item("Save Last to Folder…", enabled: hasCapture) { [weak self] in
            self?.onSaveLastToFolder?()
        })
        menu.addItem(recentCapturesItem())
        menu.addItem(.separator())

        menu.addItem(defaultFolderItem())
        let login = item("Launch at Login") { [weak self] in self?.onToggleLaunchAtLogin?() }
        login.state = launchAtLoginEnabled() ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item("Quit ShotStash", key: "q") { [weak self] in self?.onQuit?() })
        statusItem.menu = menu
    }

    // MARK: - Builders

    private func recentCapturesItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if store.captures.isEmpty {
            submenu.addItem(item("No captures yet", enabled: false) {})
        }
        for capture in store.captures {
            let title = "\(Self.timeFormatter.string(from: capture.createdAt)) — \(capture.sizeLabel)"
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.image = thumbnail(for: capture)
            let actions = NSMenu()
            actions.autoenablesItems = false
            actions.addItem(item("Copy to Clipboard") { [weak self] in self?.onCopy?(capture) })
            actions.addItem(item("Save to \(settings.defaultFolderName)") { [weak self] in self?.onSaveToDefault?(capture) })
            actions.addItem(item("Save to Folder…") { [weak self] in self?.onSaveToFolder?(capture) })
            actions.addItem(.separator())
            actions.addItem(item("Delete") { [weak self] in self?.onDelete?(capture) })
            entry.submenu = actions
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Clear All", enabled: !store.captures.isEmpty) { [weak self] in self?.onClearAll?() })
        parent.submenu = submenu
        return parent
    }

    private func defaultFolderItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Default Folder: \(settings.defaultFolderName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let path = item(settings.defaultFolder.path, enabled: false) {}
        submenu.addItem(path)
        submenu.addItem(.separator())
        submenu.addItem(item("Change…") { [weak self] in self?.onChangeDefaultFolder?() })
        submenu.addItem(item("Reset to Desktop") { [weak self] in self?.onResetDefaultFolder?() })
        parent.submenu = submenu
        return parent
    }

    /// 64 px tall thumbnail; NSImage scales on draw, so we only adjust the logical size.
    private func thumbnail(for capture: Capture) -> NSImage? {
        guard let image = NSImage(contentsOf: capture.fileURL), image.size.height > 0 else { return nil }
        let height: CGFloat = 64
        image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        return image
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
