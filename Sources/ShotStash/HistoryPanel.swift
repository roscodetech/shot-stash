import AppKit
import ShotStashCore

/// Floating, non-activating picker listing the clipboard history.
/// ↑/↓ move, ⏎ or click selects, Esc or losing key status closes.
final class HistoryPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ClipStore
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Nothing copied yet")
    var onPick: ((ClipItem) -> Void)?

    private static let rowHeight: CGFloat = 56
    private static let width: CGFloat = 360
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(store: ClipStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = Self.width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.style = .inset
        tableView.selectionHighlightStyle = .regular

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        let content = NSView()
        content.addSubview(scrollView)
        content.addSubview(emptyLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Show / hide

    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        reload()
        let rows = max(store.items.count, 1)
        let height = min(CGFloat(rows), 6) * (Self.rowHeight + 1) + 16
        var origin = NSEvent.mouseLocation
        origin.y -= height
        let frame = NSRect(origin: origin, size: NSSize(width: Self.width, height: height))
        setFrame(constrained(frame), display: false)
        makeKeyAndOrderFront(nil)
        if !store.items.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    func reload() {
        tableView.reloadData()
        emptyLabel.isHidden = !store.items.isEmpty
        scrollView.isHidden = store.items.isEmpty
    }

    /// Keeps the panel fully on the screen that contains the mouse.
    private func constrained(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return frame }
        var f = frame
        let bounds = screen.visibleFrame
        if f.maxX > bounds.maxX { f.origin.x = bounds.maxX - f.width }
        if f.minX < bounds.minX { f.origin.x = bounds.minX }
        if f.minY < bounds.minY { f.origin.y = bounds.minY }
        if f.maxY > bounds.maxY { f.origin.y = bounds.maxY - f.height }
        return f
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: close()                                  // Esc
        case 36, 76: pickSelected()                       // Return, keypad Enter
        case 125: move(by: 1)                             // ↓
        case 126: move(by: -1)                            // ↑
        default: super.keyDown(with: event)
        }
    }

    private func move(by delta: Int) {
        let count = store.items.count
        guard count > 0 else { return }
        let current = tableView.selectedRow
        let next = min(max(current + delta, 0), count - 1)
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
        close()
        onPick?(item)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { store.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = store.items[row]
        let cell = ClipRowView()
        cell.configure(with: item, time: Self.timeFormatter.string(from: item.createdAt))
        return cell
    }
}

/// One row: thumbnail (or a text glyph), preview text, time.
final class ClipRowView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 13)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor

        for view in [imageView, titleLabel, timeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(with item: ClipItem, time: String) {
        timeLabel.stringValue = time
        switch item.content {
        case let .image(url, _, _):
            imageView.image = NSImage(contentsOf: url)
            titleLabel.stringValue = item.preview
            titleLabel.textColor = .secondaryLabelColor
        case let .text(text):
            imageView.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Text")
            imageView.contentTintColor = .tertiaryLabelColor
            titleLabel.stringValue = ClipItem.preview(of: text, limit: 120)
            titleLabel.textColor = .labelColor
        }
    }
}
