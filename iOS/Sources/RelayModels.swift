import Foundation

struct RelayStatus: Codable {
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

    var provenance: String {
        var pieces: [String] = []
        if let model, !model.isEmpty { pieces.append(model.uppercased()) }
        if let capabilityCount, capabilityCount > 0 { pieces.append("\(capabilityCount) CAP") }
        if pieces.isEmpty { pieces.append(role.uppercased()) }
        return pieces.joined(separator: " / ")
    }
}

extension RelayStatus {
    static let demo = RelayStatus(
        updated: ISO8601DateFormatter().string(from: .now),
        activeCount: 4,
        attentionCount: 2,
        providers: [
            .init(id: "codex", name: "Codex", mark: "◎", active: 2, tokens: 17_200, usage: "17.2K", short: nil, week: nil, sessionCount: 3, needsAttention: 1),
            .init(id: "claude", name: "Claude", mark: "A", active: 1, tokens: 31_200, usage: "31.2K", short: nil, week: nil, sessionCount: 2, needsAttention: 1),
            .init(id: "cursor", name: "Cursor", mark: "C", active: 1, tokens: 8_900, usage: "8.9K", short: nil, week: nil, sessionCount: 1, needsAttention: 0)
        ],
        sessions: [
            .init(id: "1", provider: "Claude", mark: "A", role: "Main", title: "Choose the launch headline", project: "Momo", live: true, age: "LIVE", attention: "needsInput", attentionLabel: "NEEDS YOU", attentionReason: "The agent is waiting for your response", urgent: true, model: "Claude Sonnet", mcpServers: ["github"], skills: ["frontend-design"], plugins: [], capabilityCount: 2),
            .init(id: "2", provider: "Codex", mark: "◎", role: "Subagent", title: "Approve release packaging", project: "BAR BOY", live: true, age: "LIVE", attention: "needsInput", attentionLabel: "NEEDS YOU", attentionReason: "Approval required before publishing", urgent: true, model: "GPT-5", mcpServers: ["github", "web"], skills: ["ship"], plugins: ["Codex Security"], capabilityCount: 4),
            .init(id: "3", provider: "Cursor", mark: "C", role: "Main", title: "Refactoring the provider adapter", project: "BAR BOY", live: true, age: "LIVE", attention: "working", attentionLabel: "WORKING", attentionReason: nil, urgent: false, model: "Composer", mcpServers: [], skills: [], plugins: [], capabilityCount: 0)
        ]
    )
}
