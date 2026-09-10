import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude
    case gemini

    var id: String { rawValue }

    var name: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    var monogram: String {
        switch self {
        case .codex: return "◎"
        case .claude: return "A"
        case .gemini: return "✦"
        }
    }

    var processTerms: [String] {
        switch self {
        case .codex: return ["codex"]
        case .claude: return ["claude"]
        case .gemini: return ["gemini"]
        }
    }

    var sessionRoots: [String] {
        switch self {
        case .codex: return [".codex/sessions"]
        case .claude: return [".claude/projects"]
        case .gemini: return [".gemini/tmp"]
        }
    }

    var usageURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")
        case .claude: return URL(string: "https://claude.ai/settings/usage")
        case .gemini: return URL(string: "https://aistudio.google.com/app/usage")
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

    var id: AIProvider { provider }
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
