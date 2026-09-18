import Foundation
import SwiftUI

enum BarBoyAppInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }
}

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
        case .codex: return ["com.openai.chat", "com.openai.codex"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .gemini: return ["com.google.gemini", "com.google.GoogleGemini"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        // Grok Bot (Anysphere) ships as com.anysphere.sand; consumer Grok.app may use xAI/X ids.
        case .grok: return ["com.anysphere.sand", "com.xai.grok", "ai.x.grok", "com.x.grok"]
        }
    }

    var processTerms: [String] {
        switch self {
        case .codex: return ["codex", "chatgpt"]
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
        // xAI documents Settings → Usage on grok.com; `?_s=usage` opens that panel when signed in.
        case .grok: return URL(string: "https://grok.com/?_s=usage")
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

    /// Official login / account URL opened in the default system browser during onboarding.
    /// Opening this URL does not grant MOMO cookies or session credentials.
    var accountLoginURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/auth/login")
        case .claude: return URL(string: "https://claude.ai/login")
        case .gemini: return URL(string: "https://accounts.google.com/ServiceLogin")
        case .cursor: return URL(string: "https://authenticator.cursor.sh/")
        case .grok: return URL(string: "https://grok.com/")
        }
    }

    /// Button label for desktop-app connect rows (opens the installed app when present).
    var connectButtonTitle: String {
        switch self {
        case .codex: return "Connect ChatGPT / Codex"
        case .claude: return "Connect Claude"
        case .gemini: return "Connect Gemini"
        case .cursor: return "Connect Cursor"
        case .grok: return "Connect Grok Bot"
        }
    }

    /// Public download page for the Mac desktop app when Launch Services cannot find it.
    var desktopInstallURL: URL? {
        switch self {
        case .codex: return URL(string: "https://chatgpt.com/codex")
        case .claude: return URL(string: "https://claude.ai/download")
        case .gemini: return URL(string: "https://gemini.google.com/app")
        case .cursor: return URL(string: "https://cursor.com/download")
        case .grok: return URL(string: "https://docs.x.ai/grok-bot")
        }
    }

    /// Prefer these providers first in onboarding connect (desktop-app led).
    static var onboardingConnectOrder: [AIProvider] {
        [.claude, .cursor, .grok, .codex, .gemini]
    }

    /// Account % is not published locally today — activity-only allow stays honest (no fake Connected %).
    var supportsActivityOnlyConnect: Bool {
        switch self {
        case .grok, .gemini: return true
        case .codex, .claude, .cursor: return false
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
    case unknown

    var label: String {
        switch self {
        case .working: return "WORKING"
        case .needsInput: return "NEEDS YOU"
        case .completed: return "DONE"
        case .failed: return "FAILED"
        case .idle: return "IDLE"
        case .unknown: return "UNKNOWN"
        }
    }

    var isUrgent: Bool { self == .needsInput || self == .failed }
}

struct AgentSession: Identifiable, Hashable {
    let id: String
    let provider: AIProvider
    let role: AgentRole
    var title: String
    let detail: String
    var project: String
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
    let sourceURL: URL?
    let conversationID: String?
    var stoppedAfterUsageGrowth = false
    /// True only when the provider explicitly recorded a session/account limit event.
    let limitReached: Bool
    let recordedQuotaWindows: [RecordedQuotaWindow]
    let recordedSource: String?

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
        plugins: [String] = [],
        sourceURL: URL? = nil,
        conversationID: String? = nil,
        recordedQuotaWindows: [RecordedQuotaWindow] = [],
        recordedSource: String? = nil,
        limitReached: Bool = false
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
        self.sourceURL = sourceURL
        self.conversationID = conversationID
        self.recordedQuotaWindows = recordedQuotaWindows
        self.recordedSource = recordedSource
        self.limitReached = limitReached
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

    /// Only pass a schema-selected metadata object here. Never walk prompt text,
    /// tool arguments, available-tool catalogs, or arbitrary nested dictionaries.
    static func infer(from value: Any) -> SessionCapabilities {
        guard let record = value as? [String: Any] else { return SessionCapabilities() }
        var result = SessionCapabilities()
        for key in ["model", "model_name", "model_slug", "model_id"] {
            if let model = record[key] as? String, !model.isEmpty { result.model = String(model.prefix(80)); break }
        }
        if let name = record["tool_name"] as? String, name.hasPrefix("mcp__") {
            let parts = name.components(separatedBy: "__")
            if parts.count >= 3, !parts[1].isEmpty { result.mcpServers.insert(parts[1]) }
        }
        if let path = record["skill_path"] as? String,
           path.hasSuffix("/SKILL.md"), let range = path.range(of: "/skills/", options: .backwards) {
            let name = String(path[range.upperBound...].dropLast("/SKILL.md".count))
            if !name.isEmpty, !name.contains("/") { result.skills.insert(name) }
        }
        // Explicit observed metadata, not installation/catalog availability.
        for plugin in record["plugins"] as? [String] ?? [] where !plugin.isEmpty {
            result.plugins.insert(String(plugin.prefix(80)))
        }
        return result
    }

    static func recorded(in event: [String: Any], provider: AIProvider) -> SessionCapabilities {
        let type = event["type"] as? String
        switch provider {
        case .codex:
            let payload = event["payload"] as? [String: Any] ?? [:]
            if type == "turn_context" {
                return infer(from: ["model": payload["model"] as Any])
            }
            if type == "response_item", payload["type"] as? String == "function_call" {
                return infer(from: ["tool_name": payload["name"] as Any])
            }
        case .claude:
            if type == "assistant", let message = event["message"] as? [String: Any] {
                var result = infer(from: ["model": message["model"] as Any])
                for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
                    result.merge(infer(from: ["tool_name": block["name"] as Any]))
                }
                return result
            }
        case .gemini, .grok, .cursor:
            break // No guessed capability extraction for unverified schemas.
        }
        return SessionCapabilities()
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
        .init(provider: .gemini, current: .awaitingProvider, detail: "Gemini ConversationRecord adapter is ready; local capture requires folder authorization.", future: "Account usage will connect only through a provider-supported OAuth scope."),
        .init(provider: .cursor, current: .awaitingProvider, detail: "Local Cursor activity works now.", future: "Account usage stays linked to Cursor's official dashboard until a supported API is available."),
        .init(provider: .grok, current: .awaitingProvider, detail: "Grok Build session adapter is ready; local capture requires folder authorization.", future: "xAI usage will use an official API credential or delegated authorization when available.")
    ]
}

struct ProviderSnapshot: Identifiable {
    let provider: AIProvider
    var sessions: [AgentSession]
    let activeCount: Int
    let localTokensToday: Int
    let updatedAt: Date
    var shortWindowPercent: Int? = nil
    var weekWindowPercent: Int? = nil
    var shortWindowMinutes: Int? = nil
    var recordedQuota: RecordedQuotaWindow? = nil
    var recordedQuotas: [RecordedQuotaWindow] = []
    var quotaLabels: [String] {
        quotaLabels(now: .now)
    }

    func quotaLabels(now: Date) -> [String] {
        let windows = recordedQuotas.isEmpty ? recordedQuota.map { [$0] } ?? [] : recordedQuotas
        guard !windows.isEmpty else { return ["USAGE —", "LIMIT —"] }
        let labels = windows.sorted { $0.minutes < $1.minutes }.prefix(2).map { $0.label(now: now) }
        guard labels.count == 1 else { return labels }
        let missingWindow = windows[0].minutes >= 10080 ? "SHORT —" : "LONG —"
        return labels + [missingWindow]
    }

    var quotaLabel: String {
        if let recordedQuota { return recordedQuota.label(now: .now) }
        guard let percent = shortWindowPercent, (0...100).contains(percent),
              let minutes = shortWindowMinutes, minutes > 0 else { return "QUOTA —" }
        let window = minutes % 60 == 0 ? "\(minutes / 60)HR" : "\(minutes)MIN"
        return "\(percent)% / \(window)"
    }

    let isInstalled: Bool

    init(
        provider: AIProvider,
        sessions: [AgentSession],
        activeCount: Int,
        localTokensToday: Int,
        updatedAt: Date,
        shortWindowPercent: Int? = nil,
        weekWindowPercent: Int? = nil,
        isInstalled: Bool = true
    ) {
        self.provider = provider
        self.sessions = sessions
        self.activeCount = activeCount
        self.localTokensToday = localTokensToday
        self.updatedAt = updatedAt
        self.shortWindowPercent = shortWindowPercent
        self.weekWindowPercent = weekWindowPercent
        self.isInstalled = isInstalled
    }

    var id: AIProvider { provider }
    var needsAttentionCount: Int { sessions.filter { $0.attention.isUrgent }.count }
    func hasRecordedLimit(now: Date = .now) -> Bool {
        if sessions.contains(where: { $0.limitReached }) { return true }
        let windows = recordedQuotas.isEmpty ? recordedQuota.map { [$0] } ?? [] : recordedQuotas
        return windows.contains { $0.percent >= 100 && ($0.resetsAt == nil || $0.resetsAt! > now) }
    }
    var hasErrorOrApproval: Bool { sessions.contains { $0.attention == .failed || $0.attention == .needsInput } }
    /// A question or permission prompt is on screen somewhere.
    var waitingCount: Int { sessions.filter { $0.attention == .needsInput }.count }
    /// Something actually failed.
    var failedCount: Int { sessions.filter { $0.attention == .failed }.count }
    var statusLabel: String {
        if let urgent = sessions.first(where: { $0.attention.isUrgent }) {
            return "ISSUE · \(urgent.title)"
        }
        if let percent = primaryUsagePercent {
            return "USAGE · \(percent)%"
        }
        if sessions.contains(where: { $0.attention == .working }) { return "WORKING" }
        if sessions.contains(where: { $0.attention == .completed }) { return "DONE" }
        if activeCount > 0 { return "LIVE · \(activeCount)" }
        if sessions.isEmpty { return "STATUS —" }
        return "STATUS · UNKNOWN"
    }

    /// Best local/desktop-derived usage percent when known; never invents a value.
    var primaryUsagePercent: Int? {
        if let raw = recordedQuota?.percent ?? recordedQuotas.first?.percent {
            let percent = Int(raw.rounded())
            if (0...100).contains(percent) { return percent }
        }
        if let percent = shortWindowPercent, (0...100).contains(percent) { return percent }
        if let percent = weekWindowPercent, (0...100).contains(percent) { return percent }
        return nil
    }

    var tokenLabel: String {
        localTokensToday > 0 ? "TOKENS · \(usageText.uppercased())" : "TOKENS —"
    }

    func resetLabel(now: Date) -> String {
        let windows = recordedQuotas.isEmpty ? recordedQuota.map { [$0] } ?? [] : recordedQuotas
        guard let reset = windows.compactMap(\.resetsAt).filter({ $0 > now }).min() else { return "RESET —" }
        return "RESET · \(windows.first(where: { $0.resetsAt == reset })?.remainingLabel(now: now) ?? "—")"
    }
    var usageText: String {
        guard isInstalled else { return "Not installed" }
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


/// Session lifecycle events only. Nested tool failures and quoted text cannot
/// establish the lifecycle of their containing chat.
enum SessionSignal {
    static func recorded(in object: [String: Any], provider: AIProvider) -> (state: AgentAttention, reason: String)? {
        let type = object["type"] as? String ?? ""
        if provider == .codex, type == "event_msg", let payload = object["payload"] as? [String: Any] {
            switch payload["type"] as? String {
            case "task_started": return (.working, "A task started")
            case "task_complete": return (.completed, "The task completed")
            case "task_failed": return (.failed, "The task failed")
            case "turn_aborted": return (.idle, "The turn was interrupted")
            default: return nil
            }
        }
        if provider == .claude, type == "result" {
            if object["is_error"] as? Bool == true { return (.failed, "The session recorded an unsuccessful result") }
            if object["subtype"] as? String == "success" { return (.completed, "The session completed") }
        }
        return nil
    }
}

/// Gemini CLI ConversationRecord / JSONL recording, based on upstream
/// chatRecordingTypes.ts and loadConversationRecord (2026-09-12).
/// Public-schema fixtures are not a substitute for authorized local captures.
enum GeminiSessionAdapter {
    static func parse(_ data: Data, source: URL) -> AgentSession? {
        var metadata: [String: Any] = [:]
        var messages: [[String: Any]] = []
        func upsert(_ message: [String: Any]) {
            guard let id = message["id"] as? String else { return }
            if let index = messages.firstIndex(where: { $0["id"] as? String == id }) { messages[index] = message }
            else { messages.append(message) }
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let records = object["messages"] as? [[String: Any]] {
            metadata = object
            records.forEach(upsert)
        } else {
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            for line in text.split(separator: "\n") {
                guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                if let rewind = record["$rewindTo"] as? String {
                    if let index = messages.firstIndex(where: { $0["id"] as? String == rewind }) { messages.removeSubrange(index...) }
                    else { messages.removeAll() }
                } else if record["id"] is String {
                    upsert(record)
                } else if let update = record["$set"] as? [String: Any] {
                    metadata.merge(update) { _, new in new }
                    if let checkpoint = update["messages"] as? [[String: Any]] {
                        messages.removeAll()
                        checkpoint.forEach(upsert)
                    }
                } else if record["sessionId"] is String, record["projectHash"] is String {
                    metadata.merge(record) { _, new in new }
                } else { return nil }
            }
        }
        let timestamps = [metadata["lastUpdated"] as? String, metadata["startTime"] as? String].compactMap { $0 }
            + messages.compactMap { $0["timestamp"] as? String }
        guard let id = metadata["sessionId"] as? String, !id.isEmpty,
              metadata["projectHash"] is String,
              let updated = timestamps.compactMap(date).max() else { return nil }
        let responses = messages.filter { $0["type"] as? String == "gemini" }
        var total = 0
        var completeTokens = !responses.isEmpty
        for response in responses {
            guard let tokens = response["tokens"] as? [String: Any],
                  let value = tokens["total"] as? NSNumber,
                  String(cString: value.objCType) != "c",
                  value.doubleValue.isFinite, value.doubleValue >= 0,
                  value.doubleValue < Double(Int.max), value.doubleValue.rounded(.down) == value.doubleValue else {
                completeTokens = false; continue
            }
            let sum = total.addingReportingOverflow(value.intValue)
            if sum.overflow { completeTokens = false } else { total = sum.partialValue }
        }
        let model = responses.reversed().compactMap { $0["model"] as? String }.first
        // Tool names alone do not establish MCP server, plugin, or skill identity.
        return AgentSession(id: "gemini-\(id)", provider: .gemini,
                            role: metadata["kind"] as? String == "subagent" ? .subagent : .main,
                            title: (metadata["summary"] as? String).map { String($0.prefix(120)) } ?? "Gemini chat \(id.prefix(8))",
                            detail: "Recorded Gemini conversation; live state is not exposed",
                            project: "Local Gemini", updatedAt: updated, isRunning: false,
                            processID: nil, tokens: completeTokens ? total : nil,
                            attention: .unknown, model: model.map { String($0.prefix(80)) }, sourceURL: source)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}


/// Describes an observed sequence, never a claim that quota caused a stop.
struct SessionProgressTracker {
    private struct Observation {
        var tokens: Int?
        var state: AgentAttention
        var grewWhileWorking: Bool
        var stoppedAfterGrowth: Bool
    }
    private var previous: [String: Observation] = [:]

    mutating func update(_ snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        var next: [String: Observation] = [:]
        let updated = snapshots.map { snapshot in
            var result = snapshot
            result.sessions = snapshot.sessions.map { session in
                let key = "\(session.provider.rawValue)|\(session.conversationID ?? session.id)"
                let old = previous[key]
                let grew = old?.tokens.flatMap { before in session.tokens.map { $0 > before } } ?? false
                let newRun = session.attention == .working && old?.state != .working
                let growth = !newRun && ((old?.grewWhileWorking ?? false) || (old?.state == .working && grew))
                let stopped = session.attention == .failed || session.attention == .idle
                let observedStop = stopped && ((old?.state == .working && growth) || (old?.stoppedAfterGrowth ?? false))
                next[key] = Observation(tokens: session.tokens, state: session.attention, grewWhileWorking: growth, stoppedAfterGrowth: observedStop)
                var result = session
                result.stoppedAfterUsageGrowth = observedStop
                return result
            }
            return result
        }
        previous = next
        return updated
    }
}


struct RecordedQuotaWindow: Hashable {
    let percent: Double
    let minutes: Int
    let resetsAt: Date?
    let observedAt: Date

    func label(now: Date) -> String {
        if let resetsAt, now >= resetsAt { return "QUOTA —" }
        let base = "\(durationLabel) \(String(format: "%.0f", percent))%"
        guard let remaining = remainingLabel(now: now) else { return base }
        return "\(base) · \(remaining)"
    }

    var durationLabel: String {
        minutes == 10080 ? "WEEK" : minutes % 60 == 0 ? "\(minutes / 60)HR" : "\(minutes)MIN"
    }

    /// Coarse time until this window resets. nil when no reset was recorded.
    func remainingLabel(now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))M" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))H" }
        return "\(Int(seconds / 86_400))D"
    }

    var explanation: String {
        "Latest recorded session quota, observed \(observedAt.formatted()). Account identity is not recorded here."
    }

    /// nil: unrelated event; []: a quota observation with unavailable/invalid data.
    static func codex(in event: [String: Any]) -> [RecordedQuotaWindow]? {
        guard event["type"] as? String == "event_msg",
              let payload = event["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              payload.keys.contains("rate_limits") else { return nil }
        guard let timestamp = event["timestamp"] as? String,
              let observed = parseDate(timestamp),
              let limits = payload["rate_limits"] as? [String: Any] else { return [] }
        return ["primary", "secondary"].compactMap { key in
            guard let window = limits[key] as? [String: Any],
                  let percent = number(window["used_percent"]), (0...100).contains(percent),
                  let minutes = number(window["window_minutes"]), minutes > 0,
                  minutes < Double(Int.max), minutes.rounded(.down) == minutes else { return nil }
            var reset: Date?
            if let value = window["resets_at"], !(value is NSNull) {
                guard let seconds = number(value), seconds > 0, seconds < 32_503_680_000 else { return nil }
                reset = Date(timeIntervalSince1970: seconds)
            }
            return RecordedQuotaWindow(percent: percent, minutes: Int(minutes), resetsAt: reset, observedAt: observed)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, String(cString: value.objCType) != "c", value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
