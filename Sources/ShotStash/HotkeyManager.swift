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
