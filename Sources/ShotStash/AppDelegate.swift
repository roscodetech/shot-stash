import AppKit
import ShotStashCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings(defaults: UserDefaults(suiteName: Settings.suiteName) ?? .standard)
    let store: CaptureStore
    private let captureService = CaptureService()
    private let hotkeys = HotkeyManager()
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

        menuBar.selectionHotkeyAvailable = hotkeys.register(settings.hotkeySelection) { [weak self] in
            self?.capture(mode: .selection)
        }
        menuBar.fullScreenHotkeyAvailable = hotkeys.register(settings.hotkeyFullScreen) { [weak self] in
            self?.capture(mode: .fullScreen)
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
}
