import Foundation

/// Adapter for the local Grok Build session layout.
///
/// Grok's `updates.jsonl` is the authoritative conversation stream; `summary.json`
/// is only metadata. The adapter reads both from the same session directory and
/// reports only fields present in those records. It never treats a process as a
/// particular chat, and it leaves account quota data unavailable.
struct GrokSessionAdapter: ProviderSessionAdapter {
    let provider: AIProvider = .grok

    func session(from file: ProviderSessionFile, context: ProviderSessionContext) -> AgentSession? {
        guard file.url.lastPathComponent == "updates.jsonl" else { return nil }
        let directory = file.url.deletingLastPathComponent()
        let summary = readObject(at: directory.appendingPathComponent("summary.json")) ?? [:]
        let lines = readLines(at: file.url)
        guard !lines.isEmpty else { return nil }

        var sessionID: String?
        var title: String?
        var model: String?
        var project: String?
        var latest = file.modifiedAt
        var tokens = 0
        var sawUsage = false
        var state: AgentAttention = .unknown
        var reason: String?
        var mcpServers = Set<String>()
        var skills = Set<String>()

        if let info = summary["info"] as? [String: Any] {
            sessionID = string(info["session_id"]) ?? string(info["sessionId"])
            project = string(info["cwd"])
        }
        sessionID = sessionID ?? string(summary["session_id"]) ?? string(summary["sessionId"])
        title = string(summary["generated_title"]) ?? string(summary["session_summary"]) ?? string(summary["summary"])
        model = string(summary["current_model_id"])
        project = project ?? string(summary["cwd"])
        latest = max(latest, date(string(summary["updated_at"])) ?? latest)

        for line in lines {
            guard let object = json(line) else { continue }
            sessionID = sessionID ?? string(object["session_id"]) ?? string(object["sessionId"])
            latest = max(latest, date(string(object["timestamp"])) ?? latest)
            let type = string(object["type"]) ?? ""
            if type == "system", string(object["subtype"]) == "init" {
                model = model ?? string(object["model"])
                project = project ?? string(object["cwd"])
                if let values = object["skills"] as? [Any] { skills.formUnion(values.compactMap(string)) }
                if let servers = object["mcp_servers"] as? [[String: Any]] {
                    mcpServers.formUnion(servers.compactMap { string($0["name"]) })
                }
            }
            if type == "assistant", let message = object["message"] as? [String: Any] {
                model = model ?? string(message["model"])
            }
            if type == "result" {
                let subtype = string(object["subtype"]) ?? ""
                if stringBool(object["is_error"]) == true || subtype.hasPrefix("error_") {
                    state = .failed
                    reason = subtype.isEmpty ? "The Grok session recorded an error" : "Grok recorded \(subtype)"
                } else if subtype == "success" || subtype == "completed" {
                    state = .completed
                    reason = "The Grok session completed"
                }
                if let usage = object["usage"] as? [String: Any] {
                    let buckets = ["input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    let values = buckets.compactMap { int(usage[$0]) }
                    if values.count == buckets.count {
                        let total = values.reduce(0, +)
                        if total > 0 { tokens = max(tokens, total); sawUsage = true }
                    }
                }
            }
        }

        guard let id = sessionID, !id.isEmpty else { return nil }
        let safeProject = project.map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Local Grok"
        return AgentSession(
            id: "grok-\(id)", provider: .grok, role: .main,
            title: clean(title ?? "Grok chat \(id.prefix(8))", max: 120),
            detail: reason ?? "Recorded Grok session; live state is not exposed",
            project: safeProject, updatedAt: latest, isRunning: false, processID: nil,
            tokens: sawUsage ? tokens : nil, attention: state, attentionReason: reason,
            model: model.map { clean($0, max: 80) }, mcpServers: mcpServers.sorted(),
            skills: skills.sorted(), sourceURL: file.url, conversationID: id
        )
    }

    private func readObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func readLines(at url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func string(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func stringBool(_ value: Any?) -> Bool? { value as? Bool }

    private func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c" else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double.rounded(.down) == double, double < Double(Int.max) else { return nil }
        return number.intValue
    }

    private func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func clean(_ value: String, max length: Int) -> String {
        let oneLine = value.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count > length ? String(oneLine.prefix(length - 1)) + "…" : oneLine
    }
}
