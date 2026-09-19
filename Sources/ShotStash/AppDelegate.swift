import AppKit
import ServiceManagement
import ShotStashCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings(defaults: UserDefaults(suiteName: Settings.suiteName) ?? .standard)
    let store: CaptureStore
    private let captureService = CaptureService()
    private let hotkeys = HotkeyManager()
    private let notifications = NotificationService()
    private var menuBar: MenuBarController!

    override init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent(Settings.suiteName, isDirectory: true)
        // A stash directory we cannot create means nothing works; fail loudly.
        store = try! CaptureStore(directory: dir)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.purgeDirectory()

        menuBar = MenuBarController(settings: settings, store: store)
        menuBar.onCaptureSelection = { [weak self] in self?.capture(mode: .selection) }
        menuBar.onCaptureFullScreen = { [weak self] in self?.capture(mode: .fullScreen) }
        menuBar.onSaveLastToDefault = { [weak self] in self?.saveLast() }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.onSaveLastToFolder = { [weak self] in
            guard let self, let latest = store.latest else { return }
            saveToChosenFolder(latest)
        }
        menuBar.onCopy = { capture in ClipboardService.copy(capture) }
        menuBar.onSaveToDefault = { [weak self] capture in
            guard let self else { return }
            save(capture, to: resolvedDefaultFolder())
        }
        menuBar.onSaveToFolder = { [weak self] capture in self?.saveToChosenFolder(capture) }
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

        notifications.setup(saveTitle: settings.defaultFolderName)
        notifications.onSaveRequested = { [weak self] id in
            guard let self, let capture = store.capture(id: id) else { return }
            save(capture, to: resolvedDefaultFolder())
        }

        store.onChange = { [weak self] in self?.menuBar.rebuild() }
        menuBar.rebuild()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.clear()
    }

    // MARK: - Flows

    func capture(mode: CaptureMode) {
        let url = store.newFileURL()
        captureService.capture(mode: mode, to: url) { [weak self] produced in
            guard let self, produced else { return }
            let size = CaptureService.pixelSize(of: url)
            let capture = store.add(fileURL: url, width: size.width, height: size.height)
            ClipboardService.copy(capture)
            notifications.notify(capture)
        }
    }

    func saveLast() {
        guard let latest = store.latest else { return }
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

    func save(_ capture: Capture, to folder: URL) {
        do {
            try Saver.save(capture, to: folder)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't save screenshot"
            alert.informativeText = "Destination: \(folder.path)\n\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
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

    /// "Save Last to Folder…": picks a folder, saves there, and remembers it as the new default.
    func saveToChosenFolder(_ capture: Capture) {
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
