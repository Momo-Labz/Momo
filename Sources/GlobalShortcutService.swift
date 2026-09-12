import AppKit
import Carbon
import Combine
import SwiftUI

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case quickAsk, talk, dictate, handsFree
    var id: String { rawValue }
    var title: String { switch self { case .quickAsk: return "Quick Ask"; case .talk: return "Talk"; case .dictate: return "Dictate"; case .handsFree: return "Hands-free" } }
    var defaultBinding: ShortcutBinding {
        ShortcutBinding(key: [.quickAsk: UInt32(kVK_Space), .talk: UInt32(kVK_ANSI_T), .dictate: UInt32(kVK_ANSI_D), .handsFree: UInt32(kVK_ANSI_H)][self]!, modifiers: UInt32(controlKey | optionKey), character: self == .quickAsk ? "SPACE" : String(title.prefix(1)).uppercased())
    }
}
struct ShortcutBinding: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    let character: String
    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")].compactMap { modifiers & UInt32($0.0) != 0 ? $0.1 : nil }.joined() + " " + character
    }
    var isValid: Bool { modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 && key != UInt32(kVK_Escape) }
    func conflicts(with other: Self) -> Bool { key == other.key && modifiers == other.modifiers }
}

@MainActor
final class GlobalShortcutService: ObservableObject {
    static let shared = GlobalShortcutService()
    @Published private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:]
    @Published private(set) var enabled: [ShortcutAction: Bool] = [:]
    @Published private(set) var errors: [ShortcutAction: String] = [:]
    var isRegistered: Bool { references[.quickAsk] != nil }
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private let defaults: UserDefaults
    private let registers: Bool

    init(defaults: UserDefaults = .standard, register: Bool = true) {
        self.defaults = defaults; registers = register
        let saved = defaults.data(forKey: "shortcuts.v1").flatMap { try? JSONDecoder().decode([ShortcutAction: ShortcutBinding].self, from: $0) } ?? [:]
        let savedEnabled = defaults.data(forKey: "shortcuts.enabled.v1").flatMap { try? JSONDecoder().decode([ShortcutAction: Bool].self, from: $0) } ?? [:]
        for action in ShortcutAction.allCases {
            bindings[action] = saved[action] ?? action.defaultBinding
            enabled[action] = savedEnabled[action] ?? true
        }
        guard register else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x42425931, id.id > 0, id.id <= ShortcutAction.allCases.count else { return OSStatus(eventNotHandledErr) }
            let action = ShortcutAction.allCases[Int(id.id) - 1]
            DispatchQueue.main.async { NotificationCenter.default.post(name: .momoShortcut, object: action) }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        for action in ShortcutAction.allCases {
            if status != noErr { errors[action] = "Keyboard handler unavailable" }
            else if enabled[action] == true, let error = install(bindings[action]!, for: action) { errors[action] = error }
        }
    }

    func isEnabled(_ action: ShortcutAction) -> Bool { enabled[action] ?? true }

    @discardableResult func setEnabled(_ value: Bool, for action: ShortcutAction) -> String? {
        if value {
            guard let binding = bindings[action] else { return "No shortcut saved" }
            if registers, let error = install(binding, for: action) {
                errors[action] = error
                return error
            }
            enabled[action] = true
        } else {
            if let reference = references.removeValue(forKey: action) { UnregisterEventHotKey(reference) }
            errors[action] = nil
            enabled[action] = false
        }
        persist()
        return nil
    }

    @discardableResult func update(_ binding: ShortcutBinding, for action: ShortcutAction) -> String? {
        guard binding.isValid else { return "Include Control, Option or Command." }
        guard !bindings.contains(where: { $0.key != action && $0.value.conflicts(with: binding) }) else { return "That shortcut already belongs to another MOMO action." }
        if bindings[action] == binding && errors[action] == nil { return nil }
        if isEnabled(action), registers, let error = install(binding, for: action) { return error }
        bindings[action] = binding; errors[action] = nil
        persist()
        return nil
    }

    @discardableResult func reset(_ action: ShortcutAction) -> String? {
        update(action.defaultBinding, for: action)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "shortcuts.v1") }
        if let data = try? JSONEncoder().encode(enabled) { defaults.set(data, forKey: "shortcuts.enabled.v1") }
    }
    private func install(_ binding: ShortcutBinding, for action: ShortcutAction) -> String? {
        guard binding.isValid else { return "Invalid saved shortcut" }
        var newReference: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x42425931, id: UInt32(ShortcutAction.allCases.firstIndex(of: action)! + 1))
        guard RegisterEventHotKey(binding.key, binding.modifiers, id, GetApplicationEventTarget(), 0, &newReference) == noErr, let newReference else { return "Shortcut unavailable. Choose another combination." }
        if let old = references[action] { UnregisterEventHotKey(old) }
        references[action] = newReference
        return nil
    }
    deinit {
        for reference in references.values { UnregisterEventHotKey(reference) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
extension Notification.Name { static let momoShortcut = Notification.Name("momoShortcut") }

struct ShortcutRecorder: NSViewRepresentable {
    let onCapture: (ShortcutBinding?) -> Void
    func makeNSView(context: Context) -> KeyCaptureView { let view = KeyCaptureView(); view.capture = onCapture; return view }
    func updateNSView(_ view: KeyCaptureView, context: Context) { view.capture = onCapture }
    final class KeyCaptureView: NSView {
        var capture: ((ShortcutBinding?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == kVK_Escape { capture?(nil); return }
            var modifiers: UInt32 = 0
            for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] where event.modifierFlags.contains(flag) { modifiers |= UInt32(carbon) }
            let label = event.keyCode == kVK_Space ? "SPACE" : (event.charactersIgnoringModifiers?.uppercased() ?? "KEY \(event.keyCode)")
            capture?(ShortcutBinding(key: UInt32(event.keyCode), modifiers: modifiers, character: label))
        }
    }
}
