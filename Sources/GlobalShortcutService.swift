import Carbon
import Foundation

final class GlobalShortcutService: ObservableObject {
    @Published private(set) var isRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showCommandPalette, object: nil)
            }
            return noErr
        }
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        let identifier = EventHotKeyID(signature: 0x42425931, id: 1)
        let registered = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = installed == noErr && registered == noErr
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
