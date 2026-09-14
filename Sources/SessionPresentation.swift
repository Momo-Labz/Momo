import Foundation

/// Shared identity, ordering, and naming for every session surface.
enum SessionPresentation {
    static func relevant(_ sessions: [AgentSession], limit: Int) -> [AgentSession] {
        guard limit > 0 else { return [] }

        var unique: [String: AgentSession] = [:]
        for session in sessions {
            let key = "\(session.provider.rawValue)|\(fullIdentity(for: session))"
            if let current = unique[key] {
                if precedes(session, current) { unique[key] = session }
            } else {
                unique[key] = session
            }
        }

        return Array(unique.values.sorted(by: precedes).prefix(limit))
    }

    static func title(for session: AgentSession) -> String {
        if let title = usefulText(session.title), !isGeneratedIdentifierLabel(title, session: session) {
            return title
        }
        if let excerpt = usefulText(session.detail), !isGenericDetail(excerpt) {
            return excerpt
        }
        return "Untitled chat"
    }

    static func fullIdentity(for session: AgentSession) -> String {
        if let conversationID = session.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationID.isEmpty {
            return conversationID
        }
        return session.id
    }

    private static func precedes(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let leftPriority = priority(of: lhs)
        let rightPriority = priority(of: rhs)
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return fullIdentity(for: lhs) < fullIdentity(for: rhs)
    }

    private static func priority(of session: AgentSession) -> Int {
        if session.isRunning { return 0 }
        if session.attention.isUrgent { return 1 }
        return 2
    }

    private static func usefulText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        return cleaned.count <= 120 ? cleaned : String(cleaned.prefix(119)) + "…"
    }

    private static func isGeneratedIdentifierLabel(_ title: String, session: AgentSession) -> Bool {
        let normalized = title.lowercased()
        let generic: Set<String> = [
            "codex session", "codex task", "unnamed codex task", "codex subagent",
            "claude session", "cursor session", "grok session", "gemini session",
            "recent session", "untitled", "untitled chat"
        ]
        if generic.contains(normalized) { return true }

        let identity = fullIdentity(for: session).lowercased()
        let compactIdentity = identity.replacingOccurrences(of: "-", with: "")
        let compactTitle = normalized.replacingOccurrences(of: "-", with: "")
        if normalized == identity || compactTitle == compactIdentity { return true }
        let identifierCharacters = compactTitle.replacingOccurrences(of: " ", with: "")
        if identifierCharacters.count == 32,
           identifierCharacters.allSatisfy({ $0.isHexDigit }) { return true }
        return ["codex task · ", "grok chat ", "gemini chat ", "claude chat "]
            .contains { normalized.hasPrefix($0) }
    }

    private static func isGenericDetail(_ detail: String) -> Bool {
        let normalized = detail.lowercased()
        return normalized.hasPrefix("recent local ")
            || normalized.hasPrefix("recorded ")
            || normalized.hasPrefix("local process")
            || normalized == "fixture"
    }
}
