import XCTest
@testable import ShotStashCore

final class HotkeyTests: XCTestCase {
    func testDefaultsUseControlCommandDigits() {
        XCTAssertEqual(Hotkey.defaultSelection.keyCode, 21)
        XCTAssertEqual(Hotkey.defaultFullScreen.keyCode, 20)
        XCTAssertEqual(Hotkey.defaultSelection.modifiers, Hotkey.control | Hotkey.cmd)
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        XCTAssertEqual(Hotkey.defaultSelection.displayString, "⌃⌘4")
        let ctrl = Hotkey(keyCode: 20, modifiers: Hotkey.option | Hotkey.shift | Hotkey.cmd)
        XCTAssertEqual(ctrl.displayString, "⌥⇧⌘3")
    }

    func testUnknownKeyCodeFallsBackToNumber() {
        XCTAssertEqual(Hotkey(keyCode: 999, modifiers: 0).keyLabel, "key999")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Hotkey.defaultFullScreen)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), Hotkey.defaultFullScreen)
    }
}
