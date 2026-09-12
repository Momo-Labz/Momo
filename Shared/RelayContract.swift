import Foundation

/// The single transport contract shared by MOMO, MOMO RELAY, and the desk display.
/// Optional provenance fields keep 0.3 payloads decodable during the 0.4 migration.
struct RelayStatus: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int?
    let updated: String
    let activeCount: Int
    let attentionCount: Int
    let providers: [RelayProvider]
    let sessions: [RelaySession]
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
