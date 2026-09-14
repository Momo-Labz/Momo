import Foundation

/// The single transport contract shared by MOMO, MOMO RELAY, and the desk display.
/// Schema v2 adds policy-independent tracking observations while retaining v1 decoding.
struct RelayStatus: Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int?
    let updated: String
    let activeCount: Int
    let attentionCount: Int
    let providers: [RelayProvider]
    let sessions: [RelaySession]
    let usageObservations: [RelayUsageObservation]
    let evidence: [RelaySessionEvidence]

    init(
        schemaVersion: Int?,
        updated: String,
        activeCount: Int,
        attentionCount: Int,
        providers: [RelayProvider],
        sessions: [RelaySession],
        usageObservations: [RelayUsageObservation] = [],
        evidence: [RelaySessionEvidence] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updated = updated
        self.activeCount = activeCount
        self.attentionCount = attentionCount
        self.providers = providers
        self.sessions = sessions
        self.usageObservations = usageObservations
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, updated, activeCount, attentionCount, providers, sessions
        case usageObservations, evidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
        updated = try values.decode(String.self, forKey: .updated)
        activeCount = try values.decode(Int.self, forKey: .activeCount)
        attentionCount = try values.decode(Int.self, forKey: .attentionCount)
        providers = try values.decode([RelayProvider].self, forKey: .providers)
        sessions = try values.decode([RelaySession].self, forKey: .sessions)
        usageObservations = try values.decodeIfPresent([RelayUsageObservation].self, forKey: .usageObservations) ?? []
        evidence = try values.decodeIfPresent([RelaySessionEvidence].self, forKey: .evidence) ?? []
    }
}

struct RelayUsageObservation: Codable, Identifiable, Hashable {
    let provider: String
    let metric: String
    let percentage: Int?
    let resetsAt: String?
    let capturedAt: String
    let freshUntil: String
    let provenance: String

    var id: String { "\(provider)|\(metric)" }
}

struct RelaySessionEvidence: Codable, Identifiable, Hashable {
    let provider: String
    let sessionID: String
    let conversationID: String?
    let event: String
    let state: String
    let observedAt: String
    let source: String

    var id: String { "\(provider)|\(conversationID ?? sessionID)|\(observedAt)" }
}

struct RelayProvider: Codable, Identifiable {
    let id: String
    let name: String
    let mark: String
    let active: Int
    let tokens: Int
    let usage: String
    let short: Int?
    let week: Int?
    let sessionCount: Int
    let needsAttention: Int
}

struct RelaySession: Codable, Identifiable, Hashable {
    let id: String
    let provider: String
    let mark: String
    let role: String
    let title: String
    let project: String
    let live: Bool
    let age: String
    let attention: String
    let attentionLabel: String
    let attentionReason: String?
    let urgent: Bool
    let model: String?
    let mcpServers: [String]?
    let skills: [String]?
    let plugins: [String]?
    let capabilityCount: Int?
}
