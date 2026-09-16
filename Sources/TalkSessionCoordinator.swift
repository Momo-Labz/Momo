import Combine
import Foundation

/// Wires Talk voice capture → think → respond and keeps TalkService phase in sync.
@MainActor
final class TalkSessionCoordinator {
    static let shared = TalkSessionCoordinator()

    private weak var monitor: ActivityMonitor?
    private weak var preferences: PreferencesStore?
    private var cancellables = Set<AnyCancellable>()
    private var wasListening = false
    private var installed = false

    func install(monitor: ActivityMonitor, preferences: PreferencesStore) {
        guard !installed else { return }
        installed = true
        self.monitor = monitor
        self.preferences = preferences

        VoiceInput.shared.$state
            .combineLatest(VoiceInput.shared.$text)
            .sink { [weak self] state, text in
                self?.handleVoiceChange(state: state, text: text)
            }
            .store(in: &cancellables)

        VoiceInput.shared.$mode
            .sink { [weak self] mode in
                guard mode != .talk else { return }
                self?.wasListening = false
                TalkService.shared.noteListeningEnded()
            }
            .store(in: &cancellables)
    }

    private func handleVoiceChange(state: VoiceInput.State, text: String) {
        guard VoiceInput.shared.mode == .talk else { return }
        switch state {
        case .listening:
            wasListening = true
            TalkService.shared.noteListeningStarted()
        case .finished:
            guard wasListening, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                wasListening = false
                TalkService.shared.noteListeningEnded()
                return
            }
            wasListening = false
            TalkService.shared.typedAsk = text
            Task { await submit(text: text) }
        case .ready, .unavailable:
            wasListening = false
            TalkService.shared.noteListeningEnded()
        case .permission:
            break
        }
    }

    private func submit(text: String) async {
        guard let monitor, let preferences else { return }
        switch TalkService.shared.phase {
        case .thinking, .speaking: return
        default: break
        }
        await TalkService.shared.ask(
            prompt: text,
            snapshots: monitor.snapshots,
            observations: monitor.usageObservations,
            allowed: preferences.allowedTrackingProviders
        )
    }
}
