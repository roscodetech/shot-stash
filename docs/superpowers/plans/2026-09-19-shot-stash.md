# ShotStash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app whose hotkey captures a selection or full screen to the clipboard and a temporary stash, with on-demand saving to the Desktop or a chosen folder.

**Architecture:** Swift Package with a Foundation-only `ShotStashCore` library (store, naming, settings, hotkey model; unit tested) and an AppKit `ShotStash` executable (Carbon hotkeys, `screencapture` subprocess, pasteboard, notifications, `NSStatusItem` menu). A shell script wraps the release binary into a signed `.app`.

**Tech Stack:** Swift 6.3 toolchain (language mode 5), SwiftPM, AppKit, Carbon (hotkeys), ImageIO, UserNotifications, ServiceManagement. macOS 14+ deployment target. No third-party packages.

**Spec:** `docs/superpowers/specs/2026-09-19-shot-stash-design.md`

## Global Constraints

- Bundle identifier: `com.roscodetech.shotstash`. Used for the UserDefaults suite, the Caches subfolder and codesign identifier.
- Deployment target `.macOS(.v14)`; `swift-tools-version: 5.9`; `swiftLanguageVersions: [.v5]` (avoid Swift 6 strict-concurrency errors with Carbon callbacks).
- `ShotStashCore` must import only `Foundation` (no AppKit) so tests run headless.
- Stash capacity 10, newest first. Temp files live in `~/Library/Caches/com.roscodetech.shotstash/`. Cleared on launch and on quit.
- Default hotkeys: selection keyCode 21 (`4`) with ⌥⇧⌘, full screen keyCode 20 (`3`) with ⌥⇧⌘.
- Save filename format: `Screenshot yyyy-MM-dd 'at' HH.mm.ss.png`, collisions get ` (2)`, ` (3)`… before the extension.
- No Dock icon: `LSUIElement` true in Info.plist and `NSApp.setActivationPolicy(.accessory)` at launch.
- Signing: `Apple Development: ROSCOE KERBY (GWL7DRF898)` when available, else ad-hoc.
- Git: work on `dev`. Commit after every task. Every commit message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Run tests with `swift test` from the repo root. Run the app in development with `swift run ShotStash` (notifications are skipped when unbundled; that is expected).

---

## File Structure

| Path | Responsibility |
|---|---|
| `Package.swift` | Targets: `ShotStashCore` (lib), `ShotStash` (exe), `ShotStashCoreTests` |
| `Sources/ShotStashCore/Capture.swift` | Value type describing one capture |
| `Sources/ShotStashCore/CaptureStore.swift` | Ring of ≤10 captures, owns temp files |
| `Sources/ShotStashCore/SaveNamer.swift` | Destination filename + collision suffix |
| `Sources/ShotStashCore/Hotkey.swift` | Hotkey model, Carbon modifier bits, display string, key labels |
| `Sources/ShotStashCore/Settings.swift` | UserDefaults wrapper: default folder, hotkeys |
| `Sources/ShotStash/main.swift` | NSApplication bootstrap |
| `Sources/ShotStash/AppDelegate.swift` | Wires services; capture / save / folder flows |
| `Sources/ShotStash/HotkeyManager.swift` | Carbon `RegisterEventHotKey` |
| `Sources/ShotStash/CaptureService.swift` | `screencapture` subprocess + pixel size |
| `Sources/ShotStash/ClipboardService.swift` | Pasteboard write |
| `Sources/ShotStash/Saver.swift` | Copy temp file to destination |
| `Sources/ShotStash/NotificationService.swift` | Notification with Save action |
| `Sources/ShotStash/MenuBarController.swift` | Status item + menu |
| `Resources/Info.plist` | Bundle metadata, `LSUIElement` |
| `scripts/bundle.sh` | Binary → `.app`, codesign |
| `Makefile` | build / bundle / install / test / clean |
| `README.md` | Install, permissions, manual test checklist |
| `Tests/ShotStashCoreTests/*.swift` | Unit tests |

---

### Task 1: Package scaffold, Capture, CaptureStore

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ShotStashCore/Capture.swift`
- Create: `Sources/ShotStashCore/CaptureStore.swift`
- Create: `Sources/ShotStash/main.swift` (placeholder so the package resolves)
- Test: `Tests/ShotStashCoreTests/CaptureStoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct Capture: Identifiable, Equatable { let id: UUID; let fileURL: URL; let createdAt: Date; let width: Int; let height: Int; var sizeLabel: String }`
  - `public final class CaptureStore` with `init(directory: URL, capacity: Int = 10) throws`, `var captures: [Capture]` (newest first), `var latest: Capture?`, `var onChange: (() -> Void)?`, `func newFileURL() -> URL`, `@discardableResult func add(fileURL:width:height:createdAt:) -> Capture`, `func capture(id: UUID) -> Capture?`, `func remove(_:)`, `func clear()`, `func purgeDirectory()`

- [ ] **Step 1: Create Package.swift, .gitignore and a placeholder main**

`Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotStash",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ShotStashCore"),
        .executableTarget(
            name: "ShotStash",
            dependencies: ["ShotStashCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ShotStashCoreTests", dependencies: ["ShotStashCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
```

`.gitignore`:
```
.build/
build/
*.xcodeproj
.DS_Store
.swiftpm/
```

`Sources/ShotStash/main.swift` (temporary, replaced in Task 4):
```swift
import Foundation
print("ShotStash placeholder")
```

- [ ] **Step 2: Write the failing CaptureStore tests**

`Tests/ShotStashCoreTests/CaptureStoreTests.swift`:
```swift
import XCTest
@testable import ShotStashCore

final class CaptureStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotstash-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFile(in store: CaptureStore) throws -> URL {
        let url = store.newFileURL()
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    func testInitCreatesDirectory() throws {
        _ = try CaptureStore(directory: dir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testAddPutsNewestFirstAndSetsLatest() throws {
        let store = try CaptureStore(directory: dir)
        let a = store.add(fileURL: try makeFile(in: store), width: 10, height: 20)
        let b = store.add(fileURL: try makeFile(in: store), width: 30, height: 40)
        XCTAssertEqual(store.captures, [b, a])
        XCTAssertEqual(store.latest, b)
        XCTAssertEqual(b.sizeLabel, "30×40")
    }

    func testEvictsOldestBeyondCapacityAndDeletesItsFile() throws {
        let store = try CaptureStore(directory: dir, capacity: 2)
        let first = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        _ = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        _ = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        XCTAssertEqual(store.captures.count, 2)
        XCTAssertFalse(store.captures.contains(first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
    }

    func testRemoveDeletesFileAndFiresOnChange() throws {
        let store = try CaptureStore(directory: dir)
        var changes = 0
        store.onChange = { changes += 1 }
        let c = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        store.remove(c)
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertNil(store.latest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.fileURL.path))
        XCTAssertEqual(changes, 2)
    }

    func testCaptureByID() throws {
        let store = try CaptureStore(directory: dir)
        let c = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        XCTAssertEqual(store.capture(id: c.id), c)
        XCTAssertNil(store.capture(id: UUID()))
    }

    func testClearRemovesAllFiles() throws {
        let store = try CaptureStore(directory: dir)
        let a = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        let b = store.add(fileURL: try makeFile(in: store), width: 1, height: 1)
        store.clear()
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.fileURL.path))
    }

    func testPurgeDirectoryDeletesStaleFiles() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = dir.appendingPathComponent("stale.png")
        try Data([1, 2, 3]).write(to: stale)
        let store = try CaptureStore(directory: dir)
        store.purgeDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(store.captures.isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: compile error, `cannot find 'CaptureStore' in scope`.

- [ ] **Step 4: Implement Capture and CaptureStore**

`Sources/ShotStashCore/Capture.swift`:
```swift
import Foundation

/// One screenshot held in the temporary stash.
public struct Capture: Identifiable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let createdAt: Date
    public let width: Int
    public let height: Int

    public init(id: UUID = UUID(), fileURL: URL, createdAt: Date = Date(), width: Int, height: Int) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.width = width
        self.height = height
    }

    /// e.g. "1024×768"
    public var sizeLabel: String { "\(width)×\(height)" }
}
```

`Sources/ShotStashCore/CaptureStore.swift`:
```swift
import Foundation

/// Holds the most recent captures (newest first) and owns their temp files.
public final class CaptureStore {
    public let directory: URL
    public let capacity: Int
    public private(set) var captures: [Capture] = []
    /// Called after every mutation. Used by the menu to rebuild itself.
    public var onChange: (() -> Void)?

    private let fileManager = FileManager.default

    public init(directory: URL, capacity: Int = 10) throws {
        self.directory = directory
        self.capacity = capacity
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var latest: Capture? { captures.first }

    /// A fresh, unique PNG path inside the stash directory.
    public func newFileURL() -> URL {
        directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    }

    @discardableResult
    public func add(fileURL: URL, width: Int, height: Int, createdAt: Date = Date()) -> Capture {
        let capture = Capture(fileURL: fileURL, createdAt: createdAt, width: width, height: height)
        captures.insert(capture, at: 0)
        while captures.count > capacity {
            let evicted = captures.removeLast()
            try? fileManager.removeItem(at: evicted.fileURL)
        }
        onChange?()
        return capture
    }

    public func capture(id: UUID) -> Capture? {
        captures.first { $0.id == id }
    }

    public func remove(_ capture: Capture) {
        captures.removeAll { $0.id == capture.id }
        try? fileManager.removeItem(at: capture.fileURL)
        onChange?()
    }

    public func clear() {
        for capture in captures {
            try? fileManager.removeItem(at: capture.fileURL)
        }
        captures.removeAll()
        onChange?()
    }

    /// Deletes every file in the stash directory (leftovers from a crash) and empties the list.
    public func purgeDirectory() {
        if let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for item in items {
                try? fileManager.removeItem(at: item)
            }
        }
        captures.removeAll()
        onChange?()
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat(core): package scaffold, Capture and CaptureStore

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: SaveNamer

**Files:**
- Create: `Sources/ShotStashCore/SaveNamer.swift`
- Test: `Tests/ShotStashCoreTests/SaveNamerTests.swift`

**Interfaces:**
- Produces:
  - `public enum SaveNamer { static func baseName(for date: Date, timeZone: TimeZone = .current) -> String; static func destination(for date: Date, in folder: URL, timeZone: TimeZone = .current, exists: (URL) -> Bool) -> URL }`

- [ ] **Step 1: Write the failing tests**

`Tests/ShotStashCoreTests/SaveNamerTests.swift`:
```swift
import XCTest
@testable import ShotStashCore

final class SaveNamerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-09-19 14:52:03 UTC
    private let date = Date(timeIntervalSince1970: 1_789_829_523)
    private let folder = URL(fileURLWithPath: "/tmp/dest", isDirectory: true)

    func testBaseNameMatchesAppleConvention() {
        XCTAssertEqual(SaveNamer.baseName(for: date, timeZone: utc), "Screenshot 2026-09-19 at 14.52.03")
    }

    func testDestinationWhenNoCollision() {
        let url = SaveNamer.destination(for: date, in: folder, timeZone: utc) { _ in false }
        XCTAssertEqual(url.path, "/tmp/dest/Screenshot 2026-09-19 at 14.52.03.png")
    }

    func testDestinationAppendsCounterOnCollision() {
        let taken: Set<String> = [
            "/tmp/dest/Screenshot 2026-09-19 at 14.52.03.png",
            "/tmp/dest/Screenshot 2026-09-19 at 14.52.03 (2).png",
        ]
        let url = SaveNamer.destination(for: date, in: folder, timeZone: utc) { taken.contains($0.path) }
        XCTAssertEqual(url.path, "/tmp/dest/Screenshot 2026-09-19 at 14.52.03 (3).png")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SaveNamerTests 2>&1 | tail -20`
Expected: compile error, `cannot find 'SaveNamer' in scope`.

- [ ] **Step 3: Implement SaveNamer**

`Sources/ShotStashCore/SaveNamer.swift`:
```swift
import Foundation

/// Produces Apple-style screenshot filenames and resolves collisions.
public enum SaveNamer {
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }

    /// Returns `<folder>/<base>.png`, or `<base> (2).png`, `(3)`… when `exists` says the path is taken.
    public static func destination(
        for date: Date,
        in folder: URL,
        timeZone: TimeZone = .current,
        exists: (URL) -> Bool
    ) -> URL {
        let base = baseName(for: date, timeZone: timeZone)
        var candidate = folder.appendingPathComponent("\(base).png")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) (\(counter)).png")
            counter += 1
        }
        return candidate
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShotStashCore/SaveNamer.swift Tests/ShotStashCoreTests/SaveNamerTests.swift
git commit -m "feat(core): SaveNamer with Apple-style names and collision suffix

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Hotkey model and Settings

**Files:**
- Create: `Sources/ShotStashCore/Hotkey.swift`
- Create: `Sources/ShotStashCore/Settings.swift`
- Test: `Tests/ShotStashCoreTests/HotkeyTests.swift`
- Test: `Tests/ShotStashCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `public struct Hotkey: Codable, Equatable { var keyCode: UInt32; var modifiers: UInt32; static let cmd/shift/option/control: UInt32; static let defaultSelection/defaultFullScreen: Hotkey; var keyLabel: String; var displayString: String; var hasCommand/hasShift/hasOption/hasControl: Bool }`
  - `public final class Settings { static let suiteName: String; init(defaults: UserDefaults); var defaultFolder: URL { get set }; var defaultFolderName: String; func resetDefaultFolder(); var hotkeySelection: Hotkey { get set }; var hotkeyFullScreen: Hotkey { get set }; static var desktopURL: URL }`

- [ ] **Step 1: Write the failing tests**

`Tests/ShotStashCoreTests/HotkeyTests.swift`:
```swift
import XCTest
@testable import ShotStashCore

final class HotkeyTests: XCTestCase {
    func testDefaultsUseOptionShiftCommandDigits() {
        XCTAssertEqual(Hotkey.defaultSelection.keyCode, 21)
        XCTAssertEqual(Hotkey.defaultFullScreen.keyCode, 20)
        XCTAssertEqual(Hotkey.defaultSelection.modifiers, Hotkey.option | Hotkey.shift | Hotkey.cmd)
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        XCTAssertEqual(Hotkey.defaultSelection.displayString, "⌥⇧⌘4")
        let ctrl = Hotkey(keyCode: 20, modifiers: Hotkey.control | Hotkey.cmd)
        XCTAssertEqual(ctrl.displayString, "⌃⌘3")
    }

    func testUnknownKeyCodeFallsBackToNumber() {
        XCTAssertEqual(Hotkey(keyCode: 999, modifiers: 0).keyLabel, "key999")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Hotkey.defaultFullScreen)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), Hotkey.defaultFullScreen)
    }
}
```

`Tests/ShotStashCoreTests/SettingsTests.swift`:
```swift
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
        let custom = Hotkey(keyCode: 23, modifiers: Hotkey.control | Hotkey.option)
        settings.hotkeySelection = custom
        XCTAssertEqual(Settings(defaults: defaults).hotkeySelection, custom)
    }

    func testCorruptHotkeyFallsBackToDefault() {
        defaults.set(Data("garbage".utf8), forKey: "hotkeyFullScreen")
        XCTAssertEqual(Settings(defaults: defaults).hotkeyFullScreen, .defaultFullScreen)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: compile error, `cannot find 'Hotkey' in scope`.

- [ ] **Step 3: Implement Hotkey**

`Sources/ShotStashCore/Hotkey.swift`:
```swift
import Foundation

/// A global hotkey expressed with Carbon virtual key codes and modifier bits.
public struct Hotkey: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Carbon modifier masks (Events.h): cmdKey, shiftKey, optionKey, controlKey.
    public static let cmd: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// ⌥⇧⌘4
    public static let defaultSelection = Hotkey(keyCode: 21, modifiers: option | shift | cmd)
    /// ⌥⇧⌘3
    public static let defaultFullScreen = Hotkey(keyCode: 20, modifiers: option | shift | cmd)

    public var hasCommand: Bool { modifiers & Self.cmd != 0 }
    public var hasShift: Bool { modifiers & Self.shift != 0 }
    public var hasOption: Bool { modifiers & Self.option != 0 }
    public var hasControl: Bool { modifiers & Self.control != 0 }

    /// Printable key for the ANSI layout. Only the keys we expect people to bind.
    private static let keyLabels: [UInt32: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z", 49: "Space",
    ]

    public var keyLabel: String {
        Self.keyLabels[keyCode] ?? "key\(keyCode)"
    }

    /// Symbols in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    public var displayString: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption { s += "⌥" }
        if hasShift { s += "⇧" }
        if hasCommand { s += "⌘" }
        return s + keyLabel
    }
}
```

- [ ] **Step 4: Implement Settings**

`Sources/ShotStashCore/Settings.swift`:
```swift
import Foundation

/// UserDefaults-backed preferences. Captures themselves are never persisted.
public final class Settings {
    public static let suiteName = "com.roscodetech.shotstash"

    private enum Key {
        static let defaultFolder = "defaultFolder"
        static let hotkeySelection = "hotkeySelection"
        static let hotkeyFullScreen = "hotkeyFullScreen"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static var desktopURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    public var defaultFolder: URL {
        get {
            if let path = defaults.string(forKey: Key.defaultFolder) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return Self.desktopURL
        }
        set { defaults.set(newValue.path, forKey: Key.defaultFolder) }
    }

    public var defaultFolderName: String { defaultFolder.lastPathComponent }

    public func resetDefaultFolder() {
        defaults.removeObject(forKey: Key.defaultFolder)
    }

    public var hotkeySelection: Hotkey {
        get { hotkey(forKey: Key.hotkeySelection) ?? .defaultSelection }
        set { set(hotkey: newValue, forKey: Key.hotkeySelection) }
    }

    public var hotkeyFullScreen: Hotkey {
        get { hotkey(forKey: Key.hotkeyFullScreen) ?? .defaultFullScreen }
        set { set(hotkey: newValue, forKey: Key.hotkeyFullScreen) }
    }

    private func hotkey(forKey key: String) -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private func set(hotkey: Hotkey, forKey key: String) {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `Executed 18 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShotStashCore/Hotkey.swift Sources/ShotStashCore/Settings.swift Tests/ShotStashCoreTests/HotkeyTests.swift Tests/ShotStashCoreTests/SettingsTests.swift
git commit -m "feat(core): Hotkey model and UserDefaults Settings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: App skeleton, bundle script, Makefile

Deliverable: `make bundle` produces a signed `build/ShotStash.app` that shows a menu-bar camera icon with a Quit item and no Dock icon.

**Files:**
- Replace: `Sources/ShotStash/main.swift`
- Create: `Sources/ShotStash/AppDelegate.swift` (minimal, extended in Tasks 5–7)
- Create: `Sources/ShotStash/MenuBarController.swift` (minimal, extended in Task 6)
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`
- Create: `Makefile`

**Interfaces:**
- Produces: `final class AppDelegate: NSObject, NSApplicationDelegate` owning `settings`, `store`, `menuBar`; `final class MenuBarController { init(); func rebuild(); var onQuit: (() -> Void)? }`. Later tasks add properties and closures to both.

- [ ] **Step 1: Write main.swift**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Write the minimal AppDelegate**

`Sources/ShotStash/AppDelegate.swift`:
```swift
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
```

- [ ] **Step 3: Write the minimal MenuBarController**

`Sources/ShotStash/MenuBarController.swift`:
```swift
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
```

- [ ] **Step 4: Build and run unbundled to confirm the icon appears**

Run: `swift build 2>&1 | tail -5 && (swift run ShotStash & sleep 4; pkill -x ShotStash; echo stopped)`
Expected: build succeeds, a camera icon appears briefly in the menu bar, no Dock icon, no crash output.

- [ ] **Step 5: Write Info.plist**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>ShotStash</string>
    <key>CFBundleIdentifier</key><string>com.roscodetech.shotstash</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>ShotStash</string>
    <key>CFBundleDisplayName</key><string>ShotStash</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 ROSCODE TECH</string>
</dict>
</plist>
```

- [ ] **Step 6: Write scripts/bundle.sh**

```bash
#!/bin/bash
# Wraps the release binary into build/ShotStash.app and signs it.
# Override the identity with SHOTSTASH_SIGN_IDENTITY, or set it to "-" for ad-hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/release/ShotStash"
APP="$ROOT/build/ShotStash.app"
BUNDLE_ID="com.roscodetech.shotstash"

[ -x "$BIN" ] || { echo "Release binary missing. Run: swift build -c release" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShotStash"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${SHOTSTASH_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)"
fi
if [ -z "$IDENTITY" ]; then
  echo "No Apple Development identity found; signing ad-hoc (Screen Recording permission will re-prompt after each rebuild)." >&2
  IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
echo "Bundled: $APP (signed with: $IDENTITY)"
```

Then: `chmod +x scripts/bundle.sh`

- [ ] **Step 7: Write the Makefile**

```makefile
APP = build/ShotStash.app
DEST = /Applications/ShotStash.app

.PHONY: build bundle install test clean run

build:
	swift build -c release

bundle: build
	./scripts/bundle.sh

install: bundle
	@pkill -x ShotStash 2>/dev/null || true
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	open "$(DEST)"
	@echo "Installed to $(DEST)"

test:
	swift test

run:
	swift run ShotStash

clean:
	rm -rf .build build
```

Use a real tab character for recipe indentation.

- [ ] **Step 8: Bundle and verify signature and launch**

Run: `make bundle 2>&1 | tail -5 && codesign -dv build/ShotStash.app 2>&1 | grep -E "Identifier|Authority" && open build/ShotStash.app && sleep 3 && pgrep -x ShotStash && pkill -x ShotStash`
Expected: `Identifier=com.roscodetech.shotstash`, an `Authority=Apple Development: ...` line, a PID printed, icon visible in the menu bar while running.

- [ ] **Step 9: Commit**

```bash
git add Sources/ShotStash Resources scripts Makefile
git commit -m "feat(app): menu-bar skeleton, app bundle script and Makefile

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Capture, clipboard, save and hotkeys

Deliverable: pressing ⌥⇧⌘4 lets you select a region, the image is on the clipboard and in the stash; ⌥⇧⌘3 captures the full screen; menu has "Save Last to Desktop".

**Files:**
- Create: `Sources/ShotStash/CaptureService.swift`
- Create: `Sources/ShotStash/ClipboardService.swift`
- Create: `Sources/ShotStash/Saver.swift`
- Create: `Sources/ShotStash/HotkeyManager.swift`
- Modify: `Sources/ShotStash/AppDelegate.swift`
- Modify: `Sources/ShotStash/MenuBarController.swift`

**Interfaces:**
- Consumes: `CaptureStore`, `Settings`, `Hotkey`, `SaveNamer` from Tasks 1–3.
- Produces:
  - `enum CaptureMode { case selection, fullScreen }`
  - `final class CaptureService { func capture(mode: CaptureMode, to url: URL, completion: @escaping (Bool) -> Void); static func pixelSize(of url: URL) -> (width: Int, height: Int) }`
  - `enum ClipboardService { static func copy(_ capture: Capture) -> Bool }`
  - `enum Saver { static func save(_ capture: Capture, to folder: URL) throws -> URL }`
  - `final class HotkeyManager { @discardableResult func register(_ hotkey: Hotkey, handler: @escaping () -> Void) -> Bool; func unregisterAll() }`
  - `AppDelegate.capture(mode:)`, `AppDelegate.saveLast()`, `AppDelegate.save(_ capture: Capture, to folder: URL)`
  - `MenuBarController` closures: `onCaptureSelection`, `onCaptureFullScreen`, `onSaveLastToDefault`; properties `settings: Settings`, `store: CaptureStore` injected via init.

- [ ] **Step 1: Write CaptureService**

`Sources/ShotStash/CaptureService.swift`:
```swift
import Foundation
import ImageIO

enum CaptureMode {
    case selection
    case fullScreen
}

/// Drives Apple's /usr/sbin/screencapture so we get the native crosshair UI.
final class CaptureService {
    private var running: Process?

    /// Completion is called on the main queue with `true` when a file was produced.
    /// Esc during selection produces no file and reports `false`.
    func capture(mode: CaptureMode, to url: URL, completion: @escaping (Bool) -> Void) {
        guard running == nil else { return }  // ignore hotkey spam while a capture is up
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x", "-t", "png"]          // -x: no shutter sound
        if mode == .selection { args.insert("-i", at: 0) }  // -i: interactive; Space toggles window mode
        args.append(url.path)
        process.arguments = args
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.running = nil
                completion(FileManager.default.fileExists(atPath: url.path))
            }
        }
        do {
            try process.run()
            running = process
        } catch {
            NSLog("ShotStash: failed to launch screencapture: \(error)")
            completion(false)
        }
    }

    static func pixelSize(of url: URL) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return (0, 0) }
        return (w, h)
    }
}
```

- [ ] **Step 2: Write ClipboardService and Saver**

`Sources/ShotStash/ClipboardService.swift`:
```swift
import AppKit
import ShotStashCore

enum ClipboardService {
    /// Writes PNG and TIFF flavors so every app (Finder, browsers, terminals, Claude Code) can paste.
    @discardableResult
    static func copy(_ capture: Capture) -> Bool {
        guard let png = try? Data(contentsOf: capture.fileURL),
              let image = NSImage(data: png),
              let tiff = image.tiffRepresentation
        else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(tiff, forType: .tiff)
        return true
    }
}
```

`Sources/ShotStash/Saver.swift`:
```swift
import Foundation
import ShotStashCore

enum Saver {
    /// Copies the stashed PNG into `folder` with an Apple-style name. The stash keeps its copy.
    @discardableResult
    static func save(_ capture: Capture, to folder: URL) throws -> URL {
        let fm = FileManager.default
        let destination = SaveNamer.destination(for: capture.createdAt, in: folder) { fm.fileExists(atPath: $0.path) }
        try fm.copyItem(at: capture.fileURL, to: destination)
        return destination
    }
}
```

- [ ] **Step 3: Write HotkeyManager**

`Sources/ShotStash/HotkeyManager.swift`:
```swift
import Carbon
import Foundation
import ShotStashCore

/// Global hotkeys via Carbon. Works without the Accessibility permission.
final class HotkeyManager {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5348_5354  // 'SHST'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hotkeyID.id]?()
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Returns false when the combination is already taken by another app or the system.
    @discardableResult
    func register(_ hotkey: Hotkey, handler: @escaping () -> Void) -> Bool {
        let id = EventHotKeyID(signature: Self.signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("ShotStash: could not register hotkey \(hotkey.displayString) (status \(status))")
            return false
        }
        handlers[nextID] = handler
        refs.append(ref)
        nextID += 1
        return true
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }
}
```

- [ ] **Step 4: Extend MenuBarController with capture and save items**

Replace `Sources/ShotStash/MenuBarController.swift` with:
```swift
import AppKit
import ShotStashCore

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let store: CaptureStore

    var onCaptureSelection: (() -> Void)?
    var onCaptureFullScreen: (() -> Void)?
    var onSaveLastToDefault: (() -> Void)?
    var onQuit: (() -> Void)?

    /// Set to false by AppDelegate when Carbon refused a hotkey; the menu shows "(unavailable)".
    var selectionHotkeyAvailable = true
    var fullScreenHotkeyAvailable = true

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
        menu.addItem(.separator())

        menu.addItem(item("Quit ShotStash", key: "q") { [weak self] in self?.onQuit?() })
        statusItem.menu = menu
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
```

- [ ] **Step 5: Wire AppDelegate**

Replace `Sources/ShotStash/AppDelegate.swift` with:
```swift
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
```

- [ ] **Step 6: Build, install and verify manually**

Run: `make install 2>&1 | tail -3`
Expected: app launches from /Applications. Then, by hand:
1. Press ⌥⇧⌘4. First time: macOS asks for Screen Recording permission for ShotStash. Grant it in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch (`make install` again or `open /Applications/ShotStash.app`).
2. Press ⌥⇧⌘4, drag a region. Paste into Preview (File › New from Clipboard) or into Claude Code. Image appears.
3. Press ⌥⇧⌘4 then Esc. `ls ~/Library/Caches/com.roscodetech.shotstash` shows no new file.
4. Press ⌥⇧⌘3. Full screen is on the clipboard.
5. Menu › Save Last to Desktop. `ls ~/Desktop | grep Screenshot` shows a new `Screenshot 2026-… at ….png`. Do it again: a ` (2)` variant appears.
6. Confirm nothing was written to the Desktop by steps 2 and 4.

- [ ] **Step 7: Commit**

```bash
git add Sources/ShotStash
git commit -m "feat(app): hotkeys, screencapture, clipboard and Save Last

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Full menu: folder picker, recent captures, launch at login

**Files:**
- Modify: `Sources/ShotStash/MenuBarController.swift`
- Modify: `Sources/ShotStash/AppDelegate.swift`

**Interfaces:**
- Consumes: Task 5 `MenuBarController`, `AppDelegate.save(_:to:)`.
- Produces on `MenuBarController`: closures `onSaveLastToFolder`, `onCopy(Capture)`, `onSaveToDefault(Capture)`, `onSaveToFolder(Capture)`, `onDelete(Capture)`, `onClearAll`, `onChangeDefaultFolder`, `onResetDefaultFolder`, `onToggleLaunchAtLogin`; on `AppDelegate`: `chooseFolder() -> URL?`, `launchAtLoginEnabled: Bool`, `toggleLaunchAtLogin()`.

- [ ] **Step 1: Add folder picker and launch-at-login to AppDelegate**

Add `import ServiceManagement` at the top, and add inside the class (after `save(_:to:)`):
```swift
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
```

Then in `applicationDidFinishLaunching`, after the existing `menuBar.onQuit = ...` line, add:
```swift
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
            menuBar.rebuild()
        }
        menuBar.onResetDefaultFolder = { [weak self] in
            self?.settings.resetDefaultFolder()
            self?.menuBar.rebuild()
        }
        menuBar.launchAtLoginEnabled = { [weak self] in self?.launchAtLoginEnabled ?? false }
        menuBar.onToggleLaunchAtLogin = { [weak self] in self?.toggleLaunchAtLogin() }
```

- [ ] **Step 2: Build the full menu in MenuBarController**

Add these properties next to the existing closures:
```swift
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
```

Replace the body of `rebuild()` with:
```swift
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
```

Add these builders in the helpers section:
```swift
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
```

- [ ] **Step 3: Build, install, verify manually**

Run: `make install 2>&1 | tail -3`
Then by hand:
1. Take two captures. Open the menu › Recent Captures: two entries with thumbnails, newest first.
2. On the older one › Save to Desktop. File appears on Desktop with that capture's timestamp.
3. Save Last to Folder…: pick `~/Downloads`. File lands there, and the menu now reads "Save Last to Downloads" and "Default Folder: Downloads".
4. Default Folder › Reset to Desktop. Titles revert.
5. Recent Captures › (entry) › Delete removes it; Clear All empties the list and `ls ~/Library/Caches/com.roscodetech.shotstash` is empty.
6. Toggle Launch at Login; the checkmark flips (System Settings › General › Login Items lists ShotStash).
7. Quit ShotStash; the caches folder is empty.

- [ ] **Step 4: Commit**

```bash
git add Sources/ShotStash
git commit -m "feat(app): recent captures, folder picker and launch at login

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Notification with Save action

**Files:**
- Create: `Sources/ShotStash/NotificationService.swift`
- Modify: `Sources/ShotStash/AppDelegate.swift`

**Interfaces:**
- Consumes: `Capture`, `CaptureStore.capture(id:)`, `AppDelegate.save(_:to:)`, `resolvedDefaultFolder()`.
- Produces: `final class NotificationService: NSObject, UNUserNotificationCenterDelegate { var onSaveRequested: ((UUID) -> Void)?; func setup(saveTitle: String); func updateSaveTitle(_:); func notify(_ capture: Capture) }`

- [ ] **Step 1: Write NotificationService**

`Sources/ShotStash/NotificationService.swift`:
```swift
import Foundation
import ShotStashCore
import UserNotifications

/// Posts "Copied to clipboard" with a Save action. No-op when running unbundled (swift run),
/// because UNUserNotificationCenter requires a bundle identifier and would crash.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "com.roscodetech.shotstash.capture"
    private static let saveAction = "save"
    private static let captureKey = "captureID"

    var onSaveRequested: ((UUID) -> Void)?
    private let available = Bundle.main.bundleIdentifier != nil

    func setup(saveTitle: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        updateSaveTitle(saveTitle)
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error { NSLog("ShotStash: notification auth error: \(error)") }
        }
    }

    /// Re-registers the category so the button reflects the current default folder.
    func updateSaveTitle(_ title: String) {
        guard available else { return }
        let action = UNNotificationAction(identifier: Self.saveAction, title: "Save to \(title)", options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: [action], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func notify(_ capture: Capture) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Copied to clipboard"
        content.body = capture.sizeLabel
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.captureKey: capture.id.uuidString]
        let request = UNNotificationRequest(identifier: capture.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("ShotStash: notification failed: \(error)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == Self.saveAction,
              let raw = response.notification.request.content.userInfo[Self.captureKey] as? String,
              let id = UUID(uuidString: raw)
        else { return }
        DispatchQueue.main.async { [weak self] in self?.onSaveRequested?(id) }
    }
}
```

- [ ] **Step 2: Wire it into AppDelegate**

Add the property next to `captureService`:
```swift
    private let notifications = NotificationService()
```

In `applicationDidFinishLaunching`, before `menuBar.rebuild()`:
```swift
        notifications.setup(saveTitle: settings.defaultFolderName)
        notifications.onSaveRequested = { [weak self] id in
            guard let self, let capture = store.capture(id: id) else { return }
            save(capture, to: resolvedDefaultFolder())
        }
```

In `capture(mode:)`, after `ClipboardService.copy(capture)`:
```swift
            notifications.notify(capture)
```

Wherever `settings.defaultFolder` is set or reset (in `saveToChosenFolder`, `onChangeDefaultFolder`, `onResetDefaultFolder`, `resolvedDefaultFolder` fallback), add after the assignment:
```swift
        notifications.updateSaveTitle(settings.defaultFolderName)
```

- [ ] **Step 3: Build, install, verify manually**

Run: `make install 2>&1 | tail -3`
Then by hand:
1. First launch asks to allow notifications. Allow.
2. Capture a selection. A banner "Copied to clipboard / 1024×768" appears. Hover it and choose "Save to Desktop". The file appears on the Desktop.
3. Change the default folder to Downloads and capture again; the button reads "Save to Downloads".
4. `swift run ShotStash` still works without a crash (notifications silently skipped).

- [ ] **Step 4: Commit**

```bash
git add Sources/ShotStash
git commit -m "feat(app): capture notification with Save action

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: README, final verification, branches

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# ShotStash

Menu-bar screenshot stash for macOS. One hotkey grabs a selection (or the full screen)
straight to the clipboard and into a temporary stash. Nothing is written to the Desktop
until you ask.

## Why

Shift+Cmd+4 always saves a PNG to the Desktop; copying it takes extra clicks.
Ctrl+Shift+Cmd+4 copies but keeps nothing. ShotStash does both: copy now, save later,
to the Desktop or any folder you choose.

## Hotkeys

| Action | Default |
|---|---|
| Capture selection (Space toggles window mode, Esc cancels) | ⌥⇧⌘4 |
| Capture full screen | ⌥⇧⌘3 |

Change them by writing Carbon key codes and modifier bits to UserDefaults, e.g. ⌃⌥⌘4:

    defaults write com.roscodetech.shotstash hotkeySelection -data "$(printf '{"keyCode":21,"modifiers":6400}' | xxd -p | tr -d '\n')"

(modifiers: ⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096; add them up). Relaunch afterwards.

## Menu

- Capture Selection / Capture Full Screen
- Save Last to <folder> / Save Last to Folder… (the chosen folder becomes the new default)
- Recent Captures: last 10 with thumbnails; each has Copy, Save, Save to Folder…, Delete
- Default Folder: shows the current one, Change…, Reset to Desktop
- Launch at Login
- Quit

Captures live in `~/Library/Caches/com.roscodetech.shotstash/` and are wiped on quit and launch.
Saved files use Apple's naming: `Screenshot 2026-09-19 at 14.52.03.png`, with ` (2)` etc. on collision.

## Install

    make install      # builds, bundles, signs, copies to /Applications, launches

Requires Xcode command line tools (Swift 5.9+). Other targets: `make test`, `make bundle`, `make run`, `make clean`.

## Permissions

- **Screen & System Audio Recording**: macOS asks on the first capture. Grant it for ShotStash
  in System Settings › Privacy & Security, then relaunch the app.
- **Notifications**: optional. Enables the "Copied to clipboard" banner with a Save button.
- No Accessibility permission is needed.

The bundle is signed with an Apple Development identity when one is on the keychain, so the
Screen Recording grant survives rebuilds. With ad-hoc signing (`SHOTSTASH_SIGN_IDENTITY=-`)
macOS asks again after every `make install`.

## Manual test checklist

1. ⌥⇧⌘4, select a region, paste into Preview (File › New from Clipboard).
2. ⌥⇧⌘4 then Esc: no file appears in the caches folder.
3. ⌥⇧⌘3: full screen on the clipboard.
4. Save Last to Desktop twice: `Screenshot … .png` and `Screenshot … (2).png`.
5. Save Last to Folder… → pick Downloads → menu titles switch to Downloads.
6. Recent Captures shows thumbnails newest first; Delete and Clear All work.
7. Notification banner appears; its Save button writes the file.
8. Quit: caches folder is empty.

## Development

    swift test        # ShotStashCore unit tests
    swift run ShotStash   # unbundled; notifications are skipped
```

- [ ] **Step 2: Run the full test suite and a clean bundle**

Run: `swift test 2>&1 | tail -3 && make clean >/dev/null && make bundle 2>&1 | tail -2`
Expected: `Executed 18 tests, with 0 failures` and `Bundled: .../build/ShotStash.app (signed with: Apple Development: ...)`.

- [ ] **Step 3: Run the README manual checklist**

Run: `make install`, then work through all 8 checklist items. Record any failure and fix it before committing.

- [ ] **Step 4: Commit and create the four long-lived branches**

```bash
git add README.md
git commit -m "docs: README with install, permissions and manual checklist

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git branch dev-stable dev
git branch prod dev
git branch prod-stable dev
git branch --list
```

Expected: `dev`, `dev-stable`, `prod`, `prod-stable` all listed at the same commit.

---

# Addendum: clipboard history (spec addendum 2026-09-19)

Executed inline in the same session as the original plan; code was written directly to the files listed and is the reference.

### Task 9: ClipItem and ClipStore (core, tested)
- Replace `Capture.swift`/`CaptureStore.swift` with `ClipItem.swift`/`ClipStore.swift`.
- `ClipItem { id, createdAt, content: Content; isImage; fileURL; sizeLabel; preview }`, `ClipItem.preview(of:limit:)` collapses whitespace and truncates with "…".
- `ClipStore { items, latest, latestImage, newFileURL(), addImage(...), addText(_:) -> ClipItem?, moveToTop(_:), item(id:), remove(_:), clear(), purgeDirectory() }`.
- Tests: `ClipStoreTests` (mixed eviction, text dedup, image dedup deletes the new file, moveToTop, latestImage), `ClipItemTests` (preview).
- `Settings.hotkeyHistory` default keyCode 9 (V) ⌃⌘; test added.

### Task 10: watcher, panel, menu (app)
- `ClipboardWatcher.swift`, `HistoryPanel.swift`; adapt `ClipboardService`, `Saver`, `MenuBarController`, `AppDelegate`.
- Manual checks: copy text in any app → appears in Recent Clipboard; ⌃⌘V shows the panel; pick → ⌘V pastes; screenshots still appear once (no duplicate); Esc closes; Save actions only on images.
