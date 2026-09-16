import AppKit
import Foundation

/// Hands-free Talk about usage + current activity only (local Ollama). Never invents quotas.
@MainActor
final class TalkService: ObservableObject {
    static let shared = TalkService()

    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case upsell
        case offline
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var reply = ""
    @Published var typedAsk = ""

    let quota: TalkQuotaStore
    private let ollama: OllamaService
    private let synthesizer = NSSpeechSynthesizer()
    private var isOnboardingTrial = false

    /// Defaults are built in the MainActor init body — not as default-arg expressions —
    /// so we do not call MainActor-isolated `TalkQuotaStore` / `OllamaService.shared` from a nonisolated context.
    init(quota: TalkQuotaStore? = nil, ollama: OllamaService? = nil) {
        self.quota = quota ?? TalkQuotaStore()
        self.ollama = ollama ?? .shared
    }

    func begin(isOnboardingTrial: Bool = false) {
        self.isOnboardingTrial = isOnboardingTrial
        let access = quota.access(isOnboardingTrial: isOnboardingTrial)
        if access == .requiresPlus {
            phase = .upsell
            reply = TalkQuotaStore.UpsellCopy.inline
            return
        }
        transcript = ""
        reply = ""
        typedAsk = ""
        phase = .idle
    }

    func cancel() {
        ollama.cancel()
        synthesizer.stopSpeaking()
        phase = .idle
    }

    /// Build an honest facts block from observed snapshots — percentages only when recorded.
    static func factsBlock(
        snapshots: [ProviderSnapshot],
        observations: [ProviderUsageObservation],
        allowed: Set<AIProvider>,
        now: Date = .now
    ) -> String {
        var lines: [String] = [
            "Answer only from the facts below. If a percentage or activity is unknown, say you do not know. Never invent usage percentages or claim account quotas you cannot verify."
        ]
        let visible = snapshots.filter { allowed.contains($0.provider) }
        if visible.isEmpty {
            lines.append("No providers are allowed for tracking yet.")
            return lines.joined(separator: "\n")
        }
        for snapshot in visible {
            var parts = ["\(snapshot.provider.name):"]
            if snapshot.activeCount > 0 {
                parts.append("\(snapshot.activeCount) live process\(snapshot.activeCount == 1 ? "" : "es")")
            } else {
                parts.append(snapshot.isInstalled ? "idle / no live process" : "unavailable locally")
            }
            let working = snapshot.sessions.filter { $0.isRunning || $0.attention == .working }
            if let session = working.first ?? snapshot.sessions.first {
                parts.append("recent chat “\(session.title)” in \(session.project) · \(session.attention.label)")
            } else {
                parts.append("no recorded chats")
            }
            let obs = observations.filter { $0.provider == snapshot.provider && $0.isFresh(at: now) }
            if obs.isEmpty {
                parts.append("verified usage %: unknown")
            } else {
                for item in obs {
                    if let percent = item.percentage {
                        parts.append("\(item.metric): \(percent)% (\(item.provenance.label))")
                    } else {
                        parts.append("\(item.metric): % unknown")
                    }
                }
            }
            lines.append(parts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    func ask(
        prompt: String,
        snapshots: [ProviderSnapshot],
        observations: [ProviderUsageObservation],
        allowed: Set<AIProvider>
    ) async {
        let access = quota.access(isOnboardingTrial: isOnboardingTrial)
        if access == .requiresPlus {
            phase = .upsell
            reply = TalkQuotaStore.UpsellCopy.inline
            return
        }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .error("Ask about usage or what’s running — or type a question.")
            return
        }

        _ = quota.consume(isOnboardingTrial: isOnboardingTrial)
        isOnboardingTrial = false
        transcript = trimmed
        phase = .thinking
        await ollama.refresh(force: false)
        guard ollama.isAvailable else {
            phase = .offline
            reply = "Local Ollama is offline. Talk only answers on this Mac when a local model is ready."
            return
        }

        let facts = Self.factsBlock(snapshots: snapshots, observations: observations, allowed: allowed)
        let fullPrompt = """
        You are MOMO Talk. You answer briefly about the person's AI usage and current activity on this Mac.
        \(facts)

        Person asked: \(trimmed)
        """
        if let answer = await ollama.complete(prompt: fullPrompt, sourceRevision: "talk-v1") {
            reply = answer
            phase = .speaking
            synthesizer.startSpeaking(answer)
            // Inline upsell immediately after the last free ask completes.
            if !quota.momoPlusEntitled, quota.freeUsesRemaining == 0 {
                phase = .upsell
                reply = answer + "\n\n" + TalkQuotaStore.UpsellCopy.inline
            }
        } else {
            phase = .error(ollama.statusText)
            reply = "MOMO could not finish that answer. \(ollama.statusText)."
        }
    }

    func markPlusFromUpsell() {
        quota.setMomoPlusEntitled(true)
        phase = .idle
        reply = ""
    }

    func dismissUpsell() {
        phase = .idle
    }
}
