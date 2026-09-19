import AppKit
import ShotStashCore

/// Small floating cheat sheet listing every shortcut. Built from Settings so it reflects custom hotkeys.
final class ShortcutsWindow: NSPanel {
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
                   styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "ShotStash Shortcuts"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { orderOut(nil) } else { super.keyDown(with: event) }
    }

    func show() {
        contentView = buildContent()
        contentView?.layoutSubtreeIfNeeded()
        let size = contentView?.fittingSize ?? NSSize(width: 440, height: 400)
        setContentSize(size)
        // Centre on the screen the mouse is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 + 40))
        }
        makeKeyAndOrderFront(nil)
    }

    // MARK: - Content

    private func buildContent() -> NSView {
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active

        let folder = settings.defaultFolderName
        let sections: [(String, [(String, String)])] = [
            ("Anywhere", [
                (settings.hotkeySelection.displayString, "Capture an area: drag to select. While selecting, Space switches to window capture, Esc cancels."),
                (settings.hotkeyFullScreen.displayString, "Capture the full screen."),
                (settings.hotkeyHistory.displayString, "Open the clipboard history panel."),
            ]),
            ("In the clipboard panel", [
                ("↑ ↓  or hover", "Move between items."),
                ("⏎  or click", "Copy the item to the clipboard. Then ⌘V in any app to paste."),
                ("Space", "Open the image in Preview."),
                ("⌘S", "Save the image to \(folder)."),
                ("⇧⌘S", "Save As… (choose folder and filename)."),
                ("⌫", "Delete the item."),
                ("Esc", "Close the panel."),
                ("Right-click", "All actions for that item."),
            ]),
            ("Starting and stopping", [
                ("Start", "Open ShotStash from /Applications or Spotlight. It lives in the menu bar as a camera icon; turn on Launch at Login in the menu to start it automatically."),
                ("Quit", "Menu bar icon › Quit ShotStash. The stash is cleared on quit; only files you saved remain."),
            ]),
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 34, left: 18, bottom: 16, right: 18)

        let title = NSTextField(labelWithString: "ShotStash Shortcuts")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(title)

        for (index, section) in sections.enumerated() {
            let header = NSTextField(labelWithString: section.0.uppercased())
            header.font = .systemFont(ofSize: 10.5, weight: .semibold)
            header.textColor = .secondaryLabelColor
            stack.setCustomSpacing(index == 0 ? 10 : 16, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(header)

            let grid = NSGridView()
            grid.rowSpacing = 5
            grid.columnSpacing = 14
            grid.xPlacement = .leading
            grid.yPlacement = .top
            for (key, text) in section.1 {
                let keyLabel = NSTextField(labelWithString: key)
                keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
                keyLabel.textColor = .controlAccentColor
                let textLabel = NSTextField(wrappingLabelWithString: text)
                textLabel.font = .systemFont(ofSize: 12)
                textLabel.preferredMaxLayoutWidth = 280
                grid.addRow(with: [keyLabel, textLabel])
            }
            grid.column(at: 0).width = 110
            grid.column(at: 1).width = 290
            stack.addArrangedSubview(grid)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            glass.widthAnchor.constraint(equalToConstant: 440),
        ])
        return glass
    }
}
