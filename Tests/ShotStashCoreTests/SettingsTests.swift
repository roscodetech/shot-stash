import XCTest
@testable import ShotStashCore

final class SettingsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "shotstash.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultFolderIsDesktop() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.defaultFolder.path, Settings.desktopURL.path)
        XCTAssertEqual(settings.defaultFolderName, "Desktop")
    }

    func testDefaultFolderRoundTripAndReset() {
        let settings = Settings(defaults: defaults)
        let custom = URL(fileURLWithPath: "/tmp/Screens", isDirectory: true)
        settings.defaultFolder = custom
        XCTAssertEqual(Settings(defaults: defaults).defaultFolder.path, "/tmp/Screens")
        XCTAssertEqual(settings.defaultFolderName, "Screens")
        settings.resetDefaultFolder()
        XCTAssertEqual(settings.defaultFolder.path, Settings.desktopURL.path)
    }

    func testHotkeysDefaultAndPersist() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.hotkeySelection, .defaultSelection)
        XCTAssertEqual(settings.hotkeyFullScreen, .defaultFullScreen)
        XCTAssertEqual(settings.hotkeyHistory, .defaultHistory)
        XCTAssertEqual(Hotkey.defaultHistory.displayString, "⌃⌘V")
        let custom = Hotkey(keyCode: 23, modifiers: Hotkey.control | Hotkey.option)
        settings.hotkeySelection = custom
        XCTAssertEqual(Settings(defaults: defaults).hotkeySelection, custom)
    }

    func testCorruptHotkeyFallsBackToDefault() {
        defaults.set(Data("garbage".utf8), forKey: "hotkeyFullScreen")
        XCTAssertEqual(Settings(defaults: defaults).hotkeyFullScreen, .defaultFullScreen)
    }
}
