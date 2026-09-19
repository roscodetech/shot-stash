import AppKit
import ShotStashCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings(defaults: UserDefaults(suiteName: Settings.suiteName) ?? .standard)
    let store: CaptureStore
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
        menuBar = MenuBarController()
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.rebuild()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.clear()
    }
}
