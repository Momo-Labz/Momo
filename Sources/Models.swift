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
        attentionReason: String? = nil
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
    }

    var ageLabel: String {
        if isRunning { return "LIVE" }
        let seconds = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if seconds < 60 { return "NOW" }
        if seconds < 3_600 { return "\(seconds / 60)M" }
        if seconds < 86_400 { return "\(seconds / 3_600)H" }
        return "\(seconds / 86_400)D"
    }
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
