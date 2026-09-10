import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude
    case gemini
    case cursor
    case grok

    var id: String { rawValue }

    var name: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        }
    }

    var monogram: String {
        switch self {
        case .codex: return "◎"
        case .claude: return "A"
        case .gemini: return "✦"
        case .cursor: return "C"
        case .grok: return "X"
        }
    }

    var applicationBundleIdentifiers: [String] {
        switch self {
        case .codex: return ["com.openai.codex", "com.openai.chat"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .gemini: return []
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .grok: return []
        }
    }

    var processTerms: [String] {
        switch self {
        case .codex: return ["codex"]
        case .claude: return ["claude"]
        case .gemini: return ["gemini"]
        case .cursor: return ["cursor", "cursor-agent"]
        case .grok: return ["grok", "grokbot", "grok-bot"]
        }
    }

    var sessionRoots: [String] {
        switch self {
        case .codex: return [".codex/sessions"]
        case .claude: return [".claude/projects"]
        case .gemini: return [".gemini/tmp"]
        case .cursor: return [".cursor/projects", "Library/Application Support/Cursor/User/workspaceStorage"]
        case .grok: return [".grok/sessions", ".xai/sessions"]
        }
    }

    var usageURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")
        case .claude: return URL(string: "https://claude.ai/settings/usage")
        case .gemini: return URL(string: "https://aistudio.google.com/app/usage")
        case .cursor: return URL(string: "https://cursor.com/dashboard/usage")
        case .grok: return URL(string: "https://grok.com/")
        }
    }

    var conversationURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/codex")
        case .claude: return URL(string: "https://claude.ai/new")
        case .gemini: return URL(string: "https://gemini.google.com/app")
        case .cursor: return URL(string: "https://cursor.com/")
        case .grok: return URL(string: "https://grok.com/")
        }
    }

    func matchesProcessCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        guard !lowered.contains(".app/contents/frameworks/") else { return false }
        let candidates = command.split(whereSeparator: \.isWhitespace).prefix(5).map { token in
            URL(fileURLWithPath: String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                .lastPathComponent.lowercased()
        }
        return processTerms.contains { term in candidates.contains(term) }
    }
}

enum AgentRole: String, Codable {
    case main = "Main"
    case subagent = "Subagent"
}

enum AgentAttention: String, Codable {
    case working
    case needsInput
    case completed
    case failed
    case idle

    var label: String {
        switch self {
        case .working: return "WORKING"
        case .needsInput: return "NEEDS YOU"
        case .completed: return "DONE"
        case .failed: return "FAILED"
        case .idle: return "IDLE"
        }
    }

    var isUrgent: Bool { self == .needsInput || self == .failed }
}

struct AgentSession: Identifiable, Hashable {
    let id: String
    let provider: AIProvider
    let role: AgentRole
    let title: String
    let detail: String
    let project: String
    let updatedAt: Date
    let isRunning: Bool
    let processID: Int?
    let tokens: Int?
    let attention: AgentAttention
    let attentionReason: String?
    let model: String?
    let mcpServers: [String]
    let skills: [String]
    let plugins: [String]

    init(
        id: String,
        provider: AIProvider,
        role: AgentRole,
        title: String,
        detail: String,
        project: String,
        updatedAt: Date,
        isRunning: Bool,
        processID: Int?,
        tokens: Int?,
        attention: AgentAttention = .working,
        attentionReason: String? = nil,
        model: String? = nil,
        mcpServers: [String] = [],
        skills: [String] = [],
        plugins: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.role = role
        self.title = title
        self.detail = detail
        self.project = project
        self.updatedAt = updatedAt
        self.isRunning = isRunning
        self.processID = processID
        self.tokens = tokens
        self.attention = attention
        self.attentionReason = attentionReason
        self.model = model
        self.mcpServers = mcpServers
        self.skills = skills
        self.plugins = plugins
    }

    var ageLabel: String {
        if isRunning { return "LIVE" }
        let seconds = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if seconds < 60 { return "NOW" }
        if seconds < 3_600 { return "\(seconds / 60)M" }
        if seconds < 86_400 { return "\(seconds / 3_600)H" }
        return "\(seconds / 86_400)D"
    }

    var capabilityCount: Int {
        mcpServers.count + skills.count + plugins.count
    }

    var capabilitySummary: String {
        var parts: [String] = []
        if let model, !model.isEmpty { parts.append(model.uppercased()) }
        if !mcpServers.isEmpty { parts.append("\(mcpServers.count) MCP") }
        if !skills.isEmpty { parts.append("\(skills.count) SKILL\(skills.count == 1 ? "" : "S")") }
        if !plugins.isEmpty { parts.append("\(plugins.count) PLUGIN\(plugins.count == 1 ? "" : "S")") }
        return parts.joined(separator: " / ")
    }
}

struct SessionCapabilities: Equatable {
    var model: String?
    var mcpServers: Set<String> = []
    var skills: Set<String> = []
    var plugins: Set<String> = []

    mutating func merge(_ other: SessionCapabilities) {
        if let candidate = other.model, !candidate.isEmpty { model = candidate }
        mcpServers.formUnion(other.mcpServers)
        skills.formUnion(other.skills)
        plugins.formUnion(other.plugins)
    }

    static func infer(from value: Any) -> SessionCapabilities {
        var result = SessionCapabilities()
        inspect(value, context: nil, result: &result)
        return result
    }

    private static func inspect(_ value: Any, context: String?, result: inout SessionCapabilities) {
        if let dict = value as? [String: Any] {
            for (rawKey, child) in dict {
                let key = rawKey.lowercased().replacingOccurrences(of: "-", with: "_")
                let strings = scalarStrings(in: child)
                if ["model", "model_name", "model_slug", "model_id"].contains(key), let candidate = strings.first {
                    result.model = normalize(candidate)
                }
                if key.contains("mcp") && (key.contains("server") || key == "mcps") {
                    strings.map(normalize).filter(isUseful).forEach { result.mcpServers.insert($0) }
                }
                if key == "skill" || key == "skills" || key == "skill_name" {
                    strings.map(normalize).filter(isUseful).forEach { result.skills.insert($0) }
                }
                if key == "plugin" || key == "plugins" || key == "plugin_name" {
                    strings.map(normalize).filter { !$0.isEmpty && $0.count <= 48 }.forEach { result.plugins.insert($0) }
                }
                inspect(child, context: key, result: &result)
            }
            return
        }

        if let array = value as? [Any] {
            array.forEach { inspect($0, context: context, result: &result) }
            return
        }

        guard let text = value as? String else { return }
        let normalized = normalize(text)
        if normalized.hasPrefix("mcp__") {
            let parts = normalized.split(separator: "_", omittingEmptySubsequences: true)
            if parts.count >= 2 { result.mcpServers.insert(String(parts[1])) }
        }
        if let marker = text.range(of: "/skills/"), let suffix = text[marker.upperBound...].split(separator: "/").first {
            let skill = normalize(String(suffix))
            if isUseful(skill) { result.skills.insert(skill) }
        }
        if context == "tool_name", normalized.hasPrefix("mcp_") {
            let pieces = normalized.replacingOccurrences(of: "mcp__", with: "").split(separator: "_", omittingEmptySubsequences: true)
            if let server = pieces.first { result.mcpServers.insert(String(server)) }
        }
    }

    private static func scalarStrings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        return []
    }

    private static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastPath = trimmed.contains("/") ? URL(fileURLWithPath: trimmed).lastPathComponent : trimmed
        return String(lastPath.prefix(48))
    }

    private static func isUseful(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 48 && !value.contains(" ")
    }
}

enum AccountAccessKind: String {
    case local = "LOCAL NOW"
    case organizationAPI = "ORG API"
    case delegatedOAuth = "OAUTH"
    case awaitingProvider = "WAITING"
}

struct ProviderAccessPlan: Identifiable {
    let provider: AIProvider
    let current: AccountAccessKind
    let detail: String
    let future: String

    var id: AIProvider { provider }

    static let all: [ProviderAccessPlan] = [
        .init(provider: .codex, current: .organizationAPI, detail: "Local Codex sessions work now.", future: "OpenAI organization usage can use an admin key; ChatGPT consumer access waits for a supported delegated API."),
        .init(provider: .claude, current: .organizationAPI, detail: "Local Claude sessions work now.", future: "Anthropic organization usage can use an Admin API key; consumer-plan access waits for a supported delegated API."),
        .init(provider: .gemini, current: .awaitingProvider, detail: "Local Gemini CLI sessions work now.", future: "Account usage will connect only through a provider-supported OAuth scope."),
        .init(provider: .cursor, current: .awaitingProvider, detail: "Local Cursor activity works now.", future: "Account usage stays linked to Cursor's official dashboard until a supported API is available."),
        .init(provider: .grok, current: .awaitingProvider, detail: "Local Grok processes work now.", future: "xAI usage will use an official API credential or delegated authorization when available.")
    ]
}

struct ProviderSnapshot: Identifiable {
    let provider: AIProvider
    let sessions: [AgentSession]
    let activeCount: Int
    let localTokensToday: Int
    let updatedAt: Date
    let shortWindowPercent: Int? = nil
    let weekWindowPercent: Int? = nil

    var id: AIProvider { provider }
    var needsAttentionCount: Int { sessions.filter { $0.attention.isUrgent }.count }
    var usageText: String {
        guard localTokensToday > 0 else { return activeCount > 0 ? "\(activeCount) live" : "Idle" }
        if localTokensToday >= 1_000_000 { return String(format: "%.1fM", Double(localTokensToday) / 1_000_000) }
        if localTokensToday >= 1_000 { return String(format: "%.1fK", Double(localTokensToday) / 1_000) }
        return "\(localTokensToday)"
    }
}

extension Array where Element == ProviderSnapshot {
    static var placeholder: [ProviderSnapshot] {
        AIProvider.allCases.map {
            ProviderSnapshot(provider: $0, sessions: [], activeCount: 0, localTokensToday: 0, updatedAt: .now)
        }
    }
}
