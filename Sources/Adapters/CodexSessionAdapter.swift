import Foundation

/// Parses Codex rollout JSONL without sampling away mid-session usage or provenance events.
struct CodexSessionAdapter: ProviderSessionAdapter {
    let provider: AIProvider = .codex

    func session(
        from file: ProviderSessionFile,
        context: ProviderSessionContext
    ) -> AgentSession? {
        var metadata = Metadata()
        guard streamObjects(from: file.url, consume: { object in
            metadata.consume(object)
            if let windows = RecordedQuotaWindow.codex(in: object) { metadata.quotaWindows = windows }
        }) else { return nil }

        let fallbackTitle = metadata.isSubagent ? "Codex subagent" : "Codex session"
        return AgentSession(
            id: metadata.sessionID ?? "codex-\(file.url.path)",
            provider: provider,
            role: metadata.isSubagent ? .subagent : .main,
            title: metadata.title ?? fallbackTitle,
            detail: metadata.detail ?? "Recent local Codex session",
            project: metadata.project ?? "Local",
            updatedAt: file.modifiedAt,
            isRunning: context.isLikelyRunning(file),
            processID: nil,
            tokens: metadata.tokens,
            attention: metadata.attention,
            attentionReason: metadata.attentionReason,
            model: metadata.model,
            mcpServers: metadata.mcpServers.sorted(),
            skills: [],
            plugins: metadata.plugins.sorted(),
            sourceURL: file.url,
            recordedQuotaWindows: metadata.quotaWindows,
            recordedSource: metadata.source
        )
    }

    /// Reads bounded chunks while retaining only the current JSONL record in memory.
    private func streamObjects(
        from url: URL,
        consume: ([String: Any]) -> Void
    ) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        var buffer = Data()
        var foundObject = false

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            } catch {
                return foundObject
            }
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)

            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let line = Data(buffer[lineStart..<newline])
                lineStart = buffer.index(after: newline)
                if let object = decodeObject(line) {
                    foundObject = true
                    consume(object)
                }
            }
            if lineStart != buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
        }

        if let object = decodeObject(buffer) {
            foundObject = true
            consume(object)
        }
        return foundObject
    }

    private func decodeObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private extension CodexSessionAdapter {
    struct Metadata {
        var source: String?
        var quotaWindows: [RecordedQuotaWindow] = []
        var sessionID: String?
        var title: String?
        var detail: String?
        var project: String?
        var tokens: Int?
        var model: String?
        var isSubagent = false
        var attention: AgentAttention = .unknown
        var attentionReason: String?
        var mcpServers: Set<String> = []
        var plugins: Set<String> = []

        private var hasGoalTitle = false
        private var blockingCallIDs: Set<String> = []

        mutating func consume(_ object: [String: Any]) {
            guard let payload = object["payload"] as? [String: Any] else { return }
            let envelopeType = string(object["type"])
            let payloadType = string(payload["type"])

            switch envelopeType {
            case "session_meta":
                consumeSessionMetadata(payload)
            case "turn_context":
                consumeTurnContext(payload)
            case "event_msg":
                consumeEvent(payload, type: payloadType)
            case "response_item":
                consumeResponseItem(payload, type: payloadType)
            default:
                break
            }
        }

        private mutating func consumeSessionMetadata(_ payload: [String: Any]) {
            source = payload["source"] as? String
            sessionID = nonemptyString(payload["session_id"])
                ?? nonemptyString(payload["id"])
                ?? sessionID
            updateProject(from: payload["cwd"])

            let hasSubagentSource = (payload["source"] as? [String: Any])?["subagent"] != nil
            if payload["parent_thread_id"] is String
                || payload["forked_from_id"] is String
                || payload["agent_path"] is String
                || hasSubagentSource
                || string(payload["thread_source"]) == "subagent" {
                isSubagent = true
            }
        }

        private mutating func consumeTurnContext(_ payload: [String: Any]) {
            if let candidate = nonemptyString(payload["model"]) {
                model = clean(candidate, maximumLength: 48)
            }
            updateProject(from: payload["cwd"])
            if detail == nil, let summary = nonemptyString(payload["summary"]) {
                detail = clean(summary, maximumLength: 88)
            }
        }

        private mutating func consumeEvent(_ payload: [String: Any], type: String?) {
            switch type {
            case "token_count":
                consumeTokenCount(payload)
            case "user_message":
                setTitleIfNeeded(nonemptyString(payload["message"]))
                attention = .working
                attentionReason = nil
            case "agent_message":
                if let message = nonemptyString(payload["message"]) {
                    detail = clean(message, maximumLength: 88)
                }
                attention = .working
                attentionReason = nil
            case "thread_goal_updated":
                consumeGoal(payload["goal"])
            case "turn_aborted":
                attention = .idle
                attentionReason = "The task was stopped"
            case "task_started":
                blockingCallIDs.removeAll()
                attention = .working
                attentionReason = nil
            case "task_complete":
                if hasExplicitError(payload["error"]) {
                    attention = .failed
                    attentionReason = "The latest Codex task failed"
                } else {
                    attention = .completed
                    attentionReason = "The latest Codex task finished"
                }
                if let message = nonemptyString(payload["last_agent_message"]) {
                    detail = clean(message, maximumLength: 88)
                }
            case "request_user_input", "approval_request", "requires_action", "waiting_for_user", "needs_input":
                attention = .needsInput
                attentionReason = "Codex is waiting for your response"
            case "task_failed", "turn_failed", "failed", "error":
                attention = .failed
                attentionReason = "The latest Codex task failed"
            case "task_completed", "turn_completed", "completed":
                attention = .completed
                attentionReason = "The latest Codex task finished"
            case "mcp_tool_call_end":
                consumeMCPInvocation(payload)
            default:
                break
            }
        }

        private mutating func consumeResponseItem(_ payload: [String: Any], type: String?) {
            switch type {
            case "function_call", "custom_tool_call":
                consumeToolCall(payload)
            case "function_call_output", "custom_tool_call_output":
                attention = .working
                attentionReason = nil
                if let callID = nonemptyString(payload["call_id"]), blockingCallIDs.remove(callID) != nil {
                    blockingCallIDs.remove(callID)
                }
            case "message":
                let text = contentText(payload["content"])
                switch string(payload["role"]) {
                case "user":
                    setTitleIfNeeded(text)
                    attention = .working
                    attentionReason = nil
                case "assistant":
                    if let text { detail = clean(text, maximumLength: 88) }
                    attention = .working
                    attentionReason = nil
                default: break
                }
            default:
                break
            }
        }

        private mutating func consumeTokenCount(_ payload: [String: Any]) {
            let info = payload["info"] as? [String: Any]
            let totalUsage = info?["total_token_usage"] as? [String: Any]
            let candidate = nonnegativeInt(totalUsage?["total_tokens"])
                ?? nonnegativeInt(info?["total_tokens"])
                ?? nonnegativeInt(payload["total_tokens"])
            if let candidate {
                tokens = max(tokens ?? 0, candidate)
            }
        }

        private mutating func consumeGoal(_ value: Any?) {
            guard let goal = value as? [String: Any] else { return }
            if let objective = nonemptyString(goal["objective"]) {
                title = clean(objective, maximumLength: 68)
                hasGoalTitle = true
            }

            switch string(goal["status"]) {
            case "blocked", "needs_input", "waiting_for_user":
                attention = .needsInput
                attentionReason = "Codex is waiting for your response"
            case "failed", "error", "cancelled":
                attention = .failed
                attentionReason = "The latest Codex goal failed"
            case "complete", "completed", "done":
                attention = .completed
                attentionReason = "The latest Codex goal finished"
            case "active", "running", "working":
                attention = .working
                attentionReason = nil
            default:
                break
            }
        }

        private mutating func consumeToolCall(_ payload: [String: Any]) {
            let name = nonemptyString(payload["name"])
            let namespace = nonemptyString(payload["namespace"])
            if let server = mcpServer(name: name, namespace: namespace) {
                mcpServers.insert(server)
            }

            attention = .working
            attentionReason = nil
            guard let normalizedName = name?.lowercased() else { return }
            let blockingNames: Set<String> = [
                "approval_request", "request_user_input", "requires_action",
                "waiting_for_user", "needs_input"
            ]
            guard blockingNames.contains(normalizedName) else { return }
            if let callID = nonemptyString(payload["call_id"]) {
                blockingCallIDs.insert(callID)
            }
            attention = .needsInput
            attentionReason = "Codex is waiting for your response"
        }

        private mutating func consumeMCPInvocation(_ payload: [String: Any]) {
            if let invocation = payload["invocation"] as? [String: Any],
               let server = normalizedCapability(nonemptyString(invocation["server"])) {
                mcpServers.insert(server)
            }
            if let plugin = normalizedCapability(nonemptyString(payload["plugin_id"])) {
                plugins.insert(plugin)
            }
        }

        private mutating func setTitleIfNeeded(_ candidate: String?) {
            guard !hasGoalTitle, title == nil, let candidate else { return }
            title = clean(candidate, maximumLength: 68)
        }

        private mutating func updateProject(from value: Any?) {
            guard let path = nonemptyString(value) else { return }
            let component = URL(fileURLWithPath: path).lastPathComponent
            if !component.isEmpty { project = clean(component, maximumLength: 48) }
        }

        private func mcpServer(name: String?, namespace: String?) -> String? {
            for candidate in [namespace, name].compactMap({ $0 }) {
                let parts = candidate.components(separatedBy: "__")
                if parts.count >= 2, parts[0].lowercased() == "mcp" {
                    return normalizedCapability(parts[1])
                }
            }
            return nil
        }

        private func contentText(_ value: Any?) -> String? {
            guard let entries = value as? [[String: Any]] else { return nonemptyString(value) }
            return entries.lazy.compactMap { entry in
                guard string(entry["type"]) == "input_text" || string(entry["type"]) == "output_text" else {
                    return nil
                }
                return nonemptyString(entry["text"])
            }.first
        }

        private func hasExplicitError(_ value: Any?) -> Bool {
            switch value {
            case nil, is NSNull: return false
            case let text as String: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case let values as [Any]: return !values.isEmpty
            case let values as [String: Any]: return !values.isEmpty
            case let flag as Bool: return flag
            default: return true
            }
        }

        private func normalizedCapability(_ value: String?) -> String? {
            guard let value else { return nil }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count <= 64, !cleaned.contains(where: \.isWhitespace) else {
                return nil
            }
            return cleaned
        }

        private func string(_ value: Any?) -> String? {
            (value as? String)?.lowercased()
        }

        private func nonemptyString(_ value: Any?) -> String? {
            guard let text = value as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private func nonnegativeInt(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, number.int64Value >= 0 else { return nil }
            return Int(clamping: number.int64Value)
        }

        private func clean(_ value: String, maximumLength: Int) -> String {
            let oneLine = value
                .replacingOccurrences(of: "\n", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard oneLine.count > maximumLength else { return oneLine }
            return String(oneLine.prefix(maximumLength - 1)) + "…"
        }
    }
}
