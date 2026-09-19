import AppKit
import ShotStashCore

/// Floating, non-activating picker listing the clipboard history.
/// ↑/↓ or hover move, ⏎ or click selects, Esc or losing key status closes.
final class HistoryPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ClipStore
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Nothing copied yet")
    private var isDismissing = false
    var onPick: ((ClipItem) -> Void)?
    var onClear: (() -> Void)?

    private static let rowHeight: CGFloat = 66
    private static let width: CGFloat = 380
    private static let maxVisibleRows = 6
    private static let headerHeight: CGFloat = 36
    private static let footerHeight: CGFloat = 26
    private static let inset: CGFloat = 8

    init(store: ClipStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = buildContent()
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Building

    private func buildContent() -> NSView {
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor

        // Header
        let title = NSTextField(labelWithString: "Clipboard")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        clear.bezelStyle = .inline
        clear.controlSize = .small
        clear.font = .systemFont(ofSize: 11)
        let header = NSStackView(views: [title, NSView(), countLabel, clear])
        header.orientation = .horizontal
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 10)
        header.setHuggingPriority(.defaultLow, for: .horizontal)

        // Table
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = Self.width - Self.inset * 2
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        emptyLabel.alignment = .center
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)

        // Footer
        let hint = NSTextField(labelWithString: "↑↓ move   ⏎ copy   esc close")
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center

        let separator = NSBox()
        separator.boxType = .separator

        for view in [header, scrollView, emptyLabel, separator, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            glass.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: glass.topAnchor),
            header.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: Self.inset),
            scrollView.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -Self.inset),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -4),

            emptyLabel.centerXAnchor.constraint(equalTo: glass.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -10),
            separator.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -4),

            hint.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -6),
        ])
        return glass
    }

    // MARK: - Show / hide

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func show() {
        isDismissing = false
        reload()
        let rows = store.items.isEmpty ? 1.2 : Double(min(store.items.count, Self.maxVisibleRows))
        let listHeight = CGFloat(rows) * (Self.rowHeight + 2)
        let height = Self.headerHeight + listHeight + 4 + 1 + 4 + Self.footerHeight
        var origin = NSEvent.mouseLocation
        origin.x += 12                     // keep the pointer off the panel
        origin.y -= height + 12
        setFrame(constrained(NSRect(origin: origin, size: NSSize(width: Self.width, height: height))), display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        if !store.items.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.isDismissing = false
        })
    }

    func reload() {
        tableView.reloadData()
        let count = store.items.count
        countLabel.stringValue = count == 0 ? "" : "\(count) item\(count == 1 ? "" : "s")"
        emptyLabel.isHidden = count > 0
        scrollView.isHidden = count == 0
    }

    /// Keeps the panel fully on the screen that contains the mouse.
    private func constrained(_ frame: NSRect) -> NSRect {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return frame }
        var f = frame
        let bounds = screen.visibleFrame
        if f.maxX > bounds.maxX { f.origin.x = mouse.x - f.width - 12 }
        if f.minX < bounds.minX { f.origin.x = bounds.minX + 8 }
        if f.minY < bounds.minY { f.origin.y = mouse.y + 12 }
        if f.maxY > bounds.maxY { f.origin.y = bounds.maxY - f.height - 8 }
        return f
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    // MARK: - Actions

    @objc private func clearTapped() {
        onClear?()
        reload()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: dismiss()                                // Esc
        case 36, 76: pickSelected()                       // Return, keypad Enter
        case 125: move(by: 1)                             // ↓
        case 126: move(by: -1)                            // ↑
        default: super.keyDown(with: event)
        }
    }

    private func move(by delta: Int) {
        let count = store.items.count
        guard count > 0 else { return }
        let next = min(max(tableView.selectedRow + delta, 0), count - 1)
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func rowClicked() {
        pickSelected()
    }

    private func pickSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < store.items.count else { return }
        let item = store.items[row]
        dismiss()
        onPick?(item)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { store.items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = ClipRowView()
        cell.configure(with: store.items[row])
        cell.onHover = { [weak self, weak tableView] in
            guard let tableView, tableView.selectedRow != row, row < (self?.store.items.count ?? 0) else { return }
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
        return cell
    }
}

/// Rounded accent highlight instead of the stock full-width selection.
final class ClipTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 9, yRadius: 9).fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {}
}

/// One row: thumbnail, kind badge, preview text, relative time.
final class ClipRowView: NSView {
    private let imageView = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    var onHover: (() -> Void)?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor

        badge.font = .systemFont(ofSize: 9.5, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07)
        badge.layer?.cornerRadius = 4
        badge.layer?.masksToBounds = true
        badge.alignment = .center

        titleLabel.maximumNumberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor

        for view in [imageView, badge, titleLabel, timeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let leadingCol = imageView.trailingAnchor
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalToConstant: 50),

            badge.leadingAnchor.constraint(equalTo: leadingCol, constant: 10),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            badge.heightAnchor.constraint(equalToConstant: 15),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingCol, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 3),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])
        badge.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    func configure(with item: ClipItem) {
        let age = Date().timeIntervalSince(item.createdAt)
        timeLabel.stringValue = age < 60 ? "just now" : Self.relative.localizedString(for: item.createdAt, relativeTo: Date())

        switch item.content {
        case let .image(url, w, h):
            imageView.image = NSImage(contentsOf: url)
            imageView.contentTintColor = nil
            imageView.layer?.borderWidth = 1
            badge.stringValue = "  IMAGE · \(w)×\(h)  "
            titleLabel.stringValue = "Screenshot or copied image"
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.font = .systemFont(ofSize: 12)
        case let .text(text):
            imageView.image = NSImage(systemSymbolName: Self.looksLikeCode(text) ? "chevron.left.forwardslash.chevron.right" : "text.alignleft",
                                      accessibilityDescription: "Text")
            imageView.contentTintColor = .tertiaryLabelColor
            imageView.layer?.borderWidth = 0
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            badge.stringValue = "  TEXT · \(words) word\(words == 1 ? "" : "s")  "
            titleLabel.stringValue = Self.looksLikeCode(text)
                ? String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
                : ClipItem.preview(of: text, limit: 160)
            titleLabel.textColor = .labelColor
            titleLabel.font = Self.looksLikeCode(text)
                ? .monospacedSystemFont(ofSize: 11, weight: .regular)
                : .systemFont(ofSize: 12.5)
        }
    }

    /// Cheap heuristic: URLs, shell lines and anything with code punctuation get the monospaced treatment.
    static func looksLikeCode(_ text: String) -> Bool {
        if text.contains("://") || text.hasPrefix("$ ") || text.hasPrefix("~/") || text.hasPrefix("/") { return true }
        let codey: [String] = ["{", "}", ";", "=>", "()", "func ", "def ", "import ", "</", "-> "]
        return codey.contains { text.contains($0) }
    }
}
