import Foundation

enum TrackerTab: String, CaseIterable, Codable, Identifiable {
    case activity
    case usage
    case brain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .usage: return "Usage"
        case .brain: return "Brain"
        }
    }
}

/// A provider-authored lifecycle signal tied to one stable conversation.
struct SessionEvidence: Codable, Hashable, Identifiable {
    let provider: AIProvider
    let sessionID: String
    let conversationID: String?
    let event: String
    let state: AgentAttention
    let observedAt: Date
    let source: String

    var id: String {
        [provider.rawValue, conversationID ?? sessionID, event, String(observedAt.timeIntervalSince1970)]
            .joined(separator: "|")
    }

    var stableConversationID: String { conversationID ?? sessionID }
}

enum UsageProvenance: String, Codable, CaseIterable {
    /// A value explicitly recorded in a local provider transcript or event stream.
    case providerEvent
    /// A value read from the provider's official HTTPS usage page in an isolated view.
    case officialWeb
    /// A value extracted locally from bounded visible page text by Ollama.
    case localOllama

    var label: String {
        switch self {
        case .providerEvent: return "PROVIDER EVENT"
        case .officialWeb: return "OFFICIAL WEB"
        case .localOllama: return "LOCAL OLLAMA"
        }
    }
}

/// One observed provider usage metric or reset window. A nil percentage stays unknown.
struct ProviderUsageObservation: Codable, Hashable, Identifiable {
    let provider: AIProvider
    let metric: String
    let percentage: Int?
    let resetsAt: Date?
    let capturedAt: Date
    let freshness: TimeInterval
    let provenance: UsageProvenance

    init(
        provider: AIProvider,
        metric: String,
        percentage: Int?,
        resetsAt: Date?,
        capturedAt: Date,
        freshness: TimeInterval,
        provenance: UsageProvenance
    ) {
        self.provider = provider
        self.metric = String(metric.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.percentage = percentage.flatMap { (0...100).contains($0) ? $0 : nil }
        self.resetsAt = resetsAt
        self.capturedAt = capturedAt
        self.freshness = max(0, freshness)
        self.provenance = provenance
    }

    var id: String { "\(provider.rawValue)|\(metric.lowercased())" }
    var freshUntil: Date { capturedAt.addingTimeInterval(freshness) }

    func isFresh(at date: Date = .now) -> Bool {
        freshness > 0 && date >= capturedAt && date <= freshUntil
    }
}

struct NotificationPolicy: Codable, Equatable {
    var isEnabled: Bool
    var notifyOnNeedsInput: Bool
    var notifyOnFailure: Bool
    var notifyOnCompletion: Bool
    var notifyOnUsageReset: Bool
    var notifyOnLimitReached: Bool
    var usageThresholds: [Int]
    var usageThresholdsByProvider: [AIProvider: [Int]]

    static let availableUsageThresholds = [50, 75, 90, 100]

    init(
        isEnabled: Bool = true,
        notifyOnNeedsInput: Bool = true,
        notifyOnFailure: Bool = true,
        notifyOnCompletion: Bool = true,
        notifyOnUsageReset: Bool = true,
        notifyOnLimitReached: Bool = true,
        usageThresholds: [Int] = [75, 90, 100],
        usageThresholdsByProvider: [AIProvider: [Int]] = [:]
    ) {
        self.isEnabled = isEnabled
        self.notifyOnNeedsInput = notifyOnNeedsInput
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnCompletion = notifyOnCompletion
        self.notifyOnUsageReset = notifyOnUsageReset
        self.notifyOnLimitReached = notifyOnLimitReached
        self.usageThresholds = Self.normalized(usageThresholds)
        self.usageThresholdsByProvider = usageThresholdsByProvider.mapValues(Self.normalized)
    }

    static let standard = NotificationPolicy()

    func thresholds(for provider: AIProvider) -> [Int] {
        usageThresholdsByProvider[provider] ?? usageThresholds
    }

    private static func normalized(_ thresholds: [Int]) -> [Int] {
        Array(Set(thresholds.filter(availableUsageThresholds.contains))).sorted()
    }
}
