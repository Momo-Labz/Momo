import AppKit
import Combine
import Foundation

enum MomoAlertKind: String, CaseIterable, Identifiable {
    case sessionStopped
    case needsYou
    case usageLow
    case failure

    var id: String { rawValue }

    var legendTitle: String {
        switch self {
        case .sessionStopped: return "STOPPED"
        case .needsYou: return "NEEDS YOU"
        case .usageLow: return "USAGE LOW"
        case .failure: return "FAILED"
        }
    }
}

/// Drives header MOMO flash + optional alert sound. Mute and sound choice live in PreferencesStore.
@MainActor
final class MomoAlertPresenter: ObservableObject {
    static let shared = MomoAlertPresenter()

    @Published private(set) var isFlashing = false
    @Published private(set) var lastKind: MomoAlertKind?

    private var flashTask: Task<Void, Never>?
    private let defaults: UserDefaults

    private enum Keys {
        static let soundEnabled = "momoAlertSoundEnabled.v1"
        static let soundName = "momoAlertSoundName.v1"
        static let muted = "momoAlertMuted.v1"
    }

    static let availableSounds = ["Basso", "Blow", "Bottle", "Funk", "Glass", "Hero", "Ping", "Purr", "Sosumi", "Submarine", "Tink"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.soundEnabled)
            objectWillChange.send()
        }
    }

    var muted: Bool {
        get { defaults.bool(forKey: Keys.muted) }
        set {
            defaults.set(newValue, forKey: Keys.muted)
            objectWillChange.send()
        }
    }

    var soundName: String {
        get {
            let saved = defaults.string(forKey: Keys.soundName) ?? "Sosumi"
            return Self.availableSounds.contains(saved) ? saved : "Sosumi"
        }
        set {
            defaults.set(newValue, forKey: Keys.soundName)
            objectWillChange.send()
        }
    }

    func trigger(_ kind: MomoAlertKind, playSound: Bool = true) {
        lastKind = kind
        flashTask?.cancel()
        isFlashing = true
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_400))
            guard !Task.isCancelled else { return }
            self?.isFlashing = false
        }
        guard playSound, soundEnabled, !muted else { return }
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    func previewSound() {
        guard !muted else { return }
        NSSound(named: NSSound.Name(soundName))?.play()
    }
}
