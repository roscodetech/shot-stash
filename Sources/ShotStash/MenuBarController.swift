import AppKit
import ShotStashCore

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    var onQuit: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShotStash")
        }
    }

    func rebuild() {
        let menu = NSMenu()
        menu.addItem(item("Quit ShotStash", key: "q") { [weak self] in self?.onQuit?() })
        statusItem.menu = menu
    }

    // MARK: - Helpers

    /// Closure-backed NSMenuItem. The closure is retained via the item's representedObject.
    func item(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
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
