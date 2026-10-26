
import Foundation
import Carbon
import AppKit

@MainActor
final class GlobalHotkeyManager {

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private let onTrigger: @MainActor () -> Void

    init(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
    }

    func register() {
        guard hotkeyRef == nil else { return }

        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                MainActor.assumeIsolated {
                    manager.onTrigger()
                }

                return noErr
            },
            1,
            [eventSpec],
            userData,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            print("Shroud: Cannot install hotkey handler")
            return
        }

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x53485244), // "SHRD"
            id: 1
        )

        let modifiers = UInt32(
            controlKey | optionKey
        )

        // ANSI S key, hardware keycode 1
        let keyCode: UInt32 = 1

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            print("Shroud: Cannot register shortcut")
        }
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        // Explicitly call unregister() before releasing
        // this manager.
    }
}
