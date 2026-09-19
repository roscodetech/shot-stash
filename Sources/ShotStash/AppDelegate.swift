import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import ShotStashCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings(defaults: UserDefaults(suiteName: Settings.suiteName) ?? .standard)
    let store: ClipStore
    private let captureService = CaptureService()
    private let hotkeys = HotkeyManager()
    private let notifications = NotificationService()
    private var menuBar: MenuBarController!
    private var watcher: ClipboardWatcher!
    private var historyPanel: HistoryPanel!

    override init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent(Settings.suiteName, isDirectory: true)
        // A stash directory we cannot create means nothing works; fail loudly.
        store = try! ClipStore(directory: dir)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.purgeDirectory()

        menuBar = MenuBarController(settings: settings, store: store)
        menuBar.onCaptureSelection = { [weak self] in self?.capture(mode: .selection) }
        menuBar.onCaptureFullScreen = { [weak self] in self?.capture(mode: .fullScreen) }
        menuBar.onShowHistory = { [weak self] in self?.historyPanel.toggle() }
        menuBar.onSaveLastToDefault = { [weak self] in self?.saveLast() }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.onSaveLastToFolder = { [weak self] in
            guard let self, let latest = store.latestImage else { return }
            saveToChosenFolder(latest)
        }
        menuBar.onCopy = { capture in ClipboardService.copy(capture) }
        menuBar.onSaveToDefault = { [weak self] capture in
            guard let self else { return }
            save(capture, to: resolvedDefaultFolder())
        }
        menuBar.onSaveToFolder = { [weak self] capture in self?.saveToChosenFolder(capture) }
        menuBar.onSaveAs = { [weak self] capture in self?.saveAs(capture) }
        menuBar.onSaveLastAs = { [weak self] in
            guard let self, let latest = store.latestImage else { return }
            saveAs(latest)
        }
        menuBar.onDelete = { [weak self] capture in self?.store.remove(capture) }
        menuBar.onClearAll = { [weak self] in self?.store.clear() }
        menuBar.onChangeDefaultFolder = { [weak self] in
            guard let self, let folder = chooseFolder() else { return }
            settings.defaultFolder = folder
            notifications.updateSaveTitle(settings.defaultFolderName)
            menuBar.rebuild()
        }
        menuBar.onResetDefaultFolder = { [weak self] in
            guard let self else { return }
            settings.resetDefaultFolder()
            notifications.updateSaveTitle(settings.defaultFolderName)
            menuBar.rebuild()
        }
        menuBar.launchAtLoginEnabled = { [weak self] in self?.launchAtLoginEnabled ?? false }
        menuBar.onToggleLaunchAtLogin = { [weak self] in self?.toggleLaunchAtLogin() }

        menuBar.selectionHotkeyAvailable = hotkeys.register(settings.hotkeySelection) { [weak self] in
            self?.capture(mode: .selection)
        }
        menuBar.fullScreenHotkeyAvailable = hotkeys.register(settings.hotkeyFullScreen) { [weak self] in
            self?.capture(mode: .fullScreen)
        }
        menuBar.historyHotkeyAvailable = hotkeys.register(settings.hotkeyHistory) { [weak self] in
            self?.historyPanel.toggle()
        }

        historyPanel = HistoryPanel(store: store)
        historyPanel.onPick = { [weak self] item in
            guard let self else { return }
            ClipboardService.copy(item)
            store.moveToTop(item)
        }
        historyPanel.onClear = { [weak self] in self?.store.clear() }
        historyPanel.onPreview = { [weak self] item in self?.preview(item) }
        historyPanel.onSaveToDefault = { [weak self] item in
            guard let self else { return }
            save(item, to: resolvedDefaultFolder())
        }
        historyPanel.onSaveToFolder = { [weak self] item in self?.saveToChosenFolder(item) }
        historyPanel.onSaveAs = { [weak self] item in self?.saveAs(item) }
        historyPanel.onDelete = { [weak self] item in self?.store.remove(item) }
        historyPanel.defaultFolderName = { [weak self] in self?.settings.defaultFolderName ?? "Desktop" }

        watcher = ClipboardWatcher(store: store)
        watcher.start()

        notifications.setup(saveTitle: settings.defaultFolderName)
        notifications.onSaveRequested = { [weak self] id in
            guard let self, let capture = store.item(id: id) else { return }
            save(capture, to: resolvedDefaultFolder())
        }

        store.onChange = { [weak self] in
            self?.menuBar.rebuild()
            if self?.historyPanel?.isVisible == true { self?.historyPanel.reload() }
        }
        menuBar.rebuild()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        store.clear()
    }

    // MARK: - Flows

    func capture(mode: CaptureMode) {
        let url = store.newFileURL()
        captureService.capture(mode: mode, to: url) { [weak self] produced in
            guard let self, produced else { return }
            let size = CaptureService.pixelSize(of: url)
            guard let capture = store.addImage(fileURL: url, width: size.width, height: size.height) else { return }
            ClipboardService.copy(capture)
            notifications.notify(capture)
        }
    }

    func saveLast() {
        guard let latest = store.latestImage else { return }
        save(latest, to: resolvedDefaultFolder())
    }

    /// Falls back to the Desktop (and resets the setting) when the chosen folder no longer exists.
    func resolvedDefaultFolder() -> URL {
        var isDir: ObjCBool = false
        let folder = settings.defaultFolder
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
            return folder
        }
        settings.resetDefaultFolder()
        notifications.updateSaveTitle(settings.defaultFolderName)
        menuBar.rebuild()
        return settings.defaultFolder
    }

    /// Opens an image in the default viewer (Preview). Text items are ignored.
    func preview(_ item: ClipItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.open(url)
    }

    func save(_ capture: ClipItem, to folder: URL) {
        do {
            let saved = try Saver.save(capture, to: folder)
            notifications.notifySaved(saved)
        } catch {
            showSaveError(error, destination: folder.path)
        }
    }

    private func showSaveError(_ error: Error, destination: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't save screenshot"
        alert.informativeText = "Destination: \(destination)\n\n\(error.localizedDescription)"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Folder picker

    /// Presents a folder chooser. Returns nil when cancelled.
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for screenshots"
        panel.directoryURL = resolvedDefaultFolder()
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// "Save As…": standard save sheet with the Apple-style name prefilled. The chosen folder becomes the default.
    func saveAs(_ item: ClipItem) {
        guard let source = item.fileURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = SaveNamer.baseName(for: item.createdAt) + ".png"
        panel.directoryURL = resolvedDefaultFolder()
        panel.message = "Save screenshot as"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
            settings.defaultFolder = destination.deletingLastPathComponent()
            notifications.updateSaveTitle(settings.defaultFolderName)
            menuBar.rebuild()
            notifications.notifySaved(destination)
        } catch {
            showSaveError(error, destination: destination.path)
        }
    }

    /// "Save Last to Folder…": picks a folder, saves there, and remembers it as the new default.
    func saveToChosenFolder(_ capture: ClipItem) {
        guard let folder = chooseFolder() else { return }
        settings.defaultFolder = folder
        notifications.updateSaveTitle(settings.defaultFolderName)
        menuBar.rebuild()
        save(capture, to: folder)
    }

    // MARK: - Launch at login

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ShotStash: launch at login failed: \(error)")
        }
        menuBar.rebuild()
    }
}
