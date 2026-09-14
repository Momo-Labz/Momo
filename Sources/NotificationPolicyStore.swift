import Combine
import Foundation

@MainActor
final class NotificationPolicyStore: ObservableObject {
    @Published var policy: NotificationPolicy {
        didSet { persistPolicy() }
    }

    private let defaults: UserDefaults
    private let policyKey: String
    private let cycleKey: String
    private var notifiedThresholdCycles: Set<String>

    init(defaults: UserDefaults = .standard, keyPrefix: String = "momo.notifications") {
        self.defaults = defaults
        policyKey = "\(keyPrefix).policy.v1"
        cycleKey = "\(keyPrefix).thresholdCycles.v1"
        if let data = defaults.data(forKey: policyKey),
           let saved = try? JSONDecoder().decode(NotificationPolicy.self, from: data) {
            policy = saved
        } else {
            policy = .standard
        }
        notifiedThresholdCycles = Set(defaults.stringArray(forKey: cycleKey) ?? [])
    }

    func setThreshold(_ threshold: Int, enabled: Bool, for provider: AIProvider) {
        guard NotificationPolicy.availableUsageThresholds.contains(threshold) else { return }
        var selected = Set(policy.thresholds(for: provider))
        if enabled { selected.insert(threshold) } else { selected.remove(threshold) }
        policy.usageThresholdsByProvider[provider] = selected.sorted()
    }

    func useDefaultThresholds(for provider: AIProvider) {
        policy.usageThresholdsByProvider.removeValue(forKey: provider)
    }

    /// Returns only milestones that have not already fired in the observation's reset cycle.
    func newMilestones(for observation: ProviderUsageObservation, now: Date = .now) -> [Int] {
        guard policy.isEnabled, observation.isFresh(at: now), let percentage = observation.percentage else { return [] }
        let thresholds = policy.thresholds(for: observation.provider).filter { threshold in
            threshold < 100 || policy.notifyOnLimitReached
        }
        var newlyReached: [Int] = []
        for threshold in thresholds {
            let prefix = thresholdPrefix(for: observation, threshold: threshold)
            if percentage < threshold {
                notifiedThresholdCycles = notifiedThresholdCycles.filter { !$0.hasPrefix(prefix) }
                continue
            }
            let key = prefix + thresholdCycle(for: observation)
            if notifiedThresholdCycles.insert(key).inserted { newlyReached.append(threshold) }
        }
        persistCycles()
        return newlyReached
    }

    func clearThresholdCycles(for provider: AIProvider? = nil) {
        if let provider {
            let prefix = "\(provider.rawValue)|"
            notifiedThresholdCycles = notifiedThresholdCycles.filter { !$0.hasPrefix(prefix) }
        } else {
            notifiedThresholdCycles.removeAll()
        }
        persistCycles()
    }

    private func thresholdPrefix(for observation: ProviderUsageObservation, threshold: Int) -> String {
        "\(observation.provider.rawValue)|\(observation.metric.lowercased())|\(threshold)|"
    }

    private func thresholdCycle(for observation: ProviderUsageObservation) -> String {
        observation.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "open"
    }

    private func persistPolicy() {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: policyKey)
    }

    private func persistCycles() {
        if notifiedThresholdCycles.count > 256 {
            notifiedThresholdCycles = Set(notifiedThresholdCycles.sorted().suffix(256))
        }
        defaults.set(notifiedThresholdCycles.sorted(), forKey: cycleKey)
    }
}
