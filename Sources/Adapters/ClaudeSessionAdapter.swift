import Foundation

/// Parses Claude Code's JSONL transcript format without sampling away mid-session provenance.
struct ClaudeSessionAdapter: ProviderSessionAdapter {
    let provider: AIProvider = .claude
    func session(
        from file: ProviderSessionFile,
        context: ProviderSessionContext
    ) -> AgentSession? {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return nil }
        defer { try? handle.close() }

        var metadata = ClaudeSessionMetadata()
        forEachJSONLine(in: handle) { object in
            metadata.consume(object)
        }

        let fallbackName = humanized(file.url.deletingPathExtension().lastPathComponent)
        return AgentSession(
            id: metadata.sessionID ?? "claude-\(file.url.path)",
            provider: provider,
            role: metadata.isSidechain ? .subagent : .main,
            title: metadata.title ?? metadata.slug.map(humanized) ?? fallbackName,
            detail: metadata.detail ?? "Recent Claude session",
            project: metadata.project ?? humanized(file.url.deletingLastPathComponent().lastPathComponent),
            updatedAt: file.modifiedAt,
            isRunning: context.isLikelyRunning(file),
            processID: nil,
            tokens: metadata.tokens > 0 ? metadata.tokens : nil,
            attention: metadata.attention,
            attentionReason: metadata.attentionReason,
            model: metadata.model,
            mcpServers: metadata.mcpServers.sorted(),
            skills: metadata.skills.sorted(),
            plugins: [],
            sourceURL: file.url,
            conversationID: metadata.sessionID
        )
    }

    /// Reads every complete line while retaining only one unfinished line and one input chunk.
    private func forEachJSONLine(
        in handle: FileHandle,
        consume: ([String: Any]) -> Void
    ) {
        var pending = Data()
        let newline = UInt8(ascii: "\n")

        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            var lineStart = pending.startIndex
            while let boundary = pending[lineStart...].firstIndex(of: newline) {
                decode(pending[lineStart..<boundary], consume: consume)
                lineStart = pending.index(after: boundary)
            }
            if lineStart != pending.startIndex {
                pending.removeSubrange(pending.startIndex..<lineStart)
            }
        }
        if !pending.isEmpty {
            decode(pending[...], consume: consume)
        }
    }

    private func decode(
        _ bytes: Data.SubSequence,
        consume: ([String: Any]) -> Void
    ) {
        guard !bytes.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any] else {
            return
        }
        consume(object)
    }

    private func humanized(_ value: String) -> String {
        let words = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return words.isEmpty ? "Untitled" : words.capitalized
    }
}

private struct ClaudeSessionMetadata {
    var title: String?
    var detail: String?
    var project: String?
    var slug: String?
    var sessionID: String?
    var model: String?
    var tokens = 0
    var isSidechain = false
    var attention: AgentAttention = .unknown
    var attentionReason: String?
    var mcpServers: Set<String> = []
    var skills: Set<String> = []
    /// Tool calls with no matching tool_result yet, newest last.
    var openToolCalls: [(id: String, name: String)] = []

    mutating func consume(_ event: [String: Any]) {
        if sessionID == nil { sessionID = nonemptyString(event["sessionId"]) ?? nonemptyString(event["session_id"]) }
        if event["isSidechain"] as? Bool == true { isSidechain = true }
        if let cwd = nonemptyString(event["cwd"]) { project = projectName(from: cwd) }
        if slug == nil { slug = nonemptyString(event["slug"]) }

        let eventType = normalized(event["type"] as? String)
        let subtype = normalized(event["subtype"] as? String)
        let status = normalized(event["status"] as? String)
        let message = event["message"] as? [String: Any]

        if let candidate = nonemptyString(message?["model"]), !candidate.hasPrefix("<") {
            model = candidate
        }
        if let usage = message?["usage"] as? [String: Any] {
            addUsage(usage)
        }

        let content = message?["content"]
        if eventType == "user", let text = cleanText(from: content, max: 88) {
            if title == nil { title = clean(text, max: 68) }
        } else if eventType == "assistant", let text = cleanText(from: content, max: 88) {
            detail = text
        }

        // A tool_result closes the call it answers.
        for id in toolResultIDs(in: content) {
            openToolCalls.removeAll { $0.id == id }
        }

        let toolUses = toolUseBlocks(in: content)
        for tool in toolUses {
            guard let name = nonemptyString(tool["name"]) else { continue }
            if let id = nonemptyString(tool["id"]) { openToolCalls.append((id: id, name: name)) }
            if let server = mcpServer(from: name) { mcpServers.insert(server) }
            if normalized(name) == "skill",
               let input = tool["input"] as? [String: Any],
               let skill = skillName(from: input) {
                skills.insert(skill)
            }
        }

        if isFailure(event: event, message: message, content: content, type: eventType, subtype: subtype, status: status) {
            attention = .failed
            attentionReason = "The latest Claude event failed"
        } else if toolUses.contains(where: isUserInputTool) || isBlocked(type: eventType, subtype: subtype, status: status) {
            attention = .needsInput
            attentionReason = "Claude is waiting for your response"
        } else if isCompleted(message: message, type: eventType, subtype: subtype, status: status) {
            attention = .completed
            attentionReason = "Claude finished the latest task"
        } else if eventType == "user" || eventType == "assistant" {
            attention = .working
            attentionReason = nil
        }
    }

    private mutating func addUsage(_ usage: [String: Any]) {
        for key in ["input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"] {
            guard let number = usage[key] as? NSNumber else { continue }
            let value = max(0, number.intValue)
            tokens = value > Int.max - tokens ? Int.max : tokens + value
        }
    }

    private func toolUseBlocks(in content: Any?) -> [[String: Any]] {
        guard let blocks = content as? [Any] else { return [] }
        return blocks.compactMap { block in
            guard let object = block as? [String: Any],
                  normalized(object["type"] as? String) == "tool_use" else { return nil }
            return object
        }
    }

    private func mcpServer(from toolName: String) -> String? {
        guard toolName.hasPrefix("mcp__") else { return nil }
        let suffix = String(toolName.dropFirst("mcp__".count))
        guard let server = suffix.components(separatedBy: "__").first else { return nil }
        return identifier(server)
    }

    private func skillName(from input: [String: Any]) -> String? {
        for key in ["skill", "skill_name", "name", "command"] {
            guard var candidate = nonemptyString(input[key]) else { continue }
            if candidate.hasPrefix("/") { candidate.removeFirst() }
            if let result = identifier(candidate) { return result }
        }
        return nil
    }

    private func toolResultIDs(in content: Any?) -> [String] {
        guard let blocks = content as? [Any] else { return [] }
        return blocks.compactMap { block in
            guard let object = block as? [String: Any],
                  normalized(object["type"] as? String) == "tool_result" else { return nil }
            return nonemptyString(object["tool_use_id"])
        }
    }

    private func isUserInputTool(_ tool: [String: Any]) -> Bool {
        guard let name = tool["name"] as? String else { return false }
        return ["askuserquestion", "request_user_input", "requestuserinput"]
            .contains(normalized(name))
    }

    private func isBlocked(type: String, subtype: String, status: String) -> Bool {
        let signals = [type, subtype, status]
        return signals.contains { ["permission_request", "approval_request", "waiting_for_user", "needs_input", "requires_action"].contains($0) }
    }

    private func isFailure(
        event: [String: Any],
        message: [String: Any]?,
        content: Any?,
        type: String,
        subtype: String,
        status: String
    ) -> Bool {
        if event["is_error"] as? Bool == true || message?["is_error"] as? Bool == true { return true }
        if [type, subtype, status].contains(where: { ["error", "failed", "failure", "cancelled"].contains($0) }) {
            return true
        }
        guard let blocks = content as? [Any] else { return false }
        return blocks.contains { block in
            guard let object = block as? [String: Any],
                  normalized(object["type"] as? String) == "tool_result" else { return false }
            return object["is_error"] as? Bool == true
        }
    }

    private func isCompleted(
        message: [String: Any]?,
        type: String,
        subtype: String,
        status: String
    ) -> Bool {
        if type == "result" && ["success", "completed", "complete"].contains(subtype) { return true }
        if ["completed", "complete", "finished", "done", "success"].contains(status) { return true }
        let stopReason = normalized(message?["stop_reason"] as? String)
        return ["end_turn", "stop_sequence"].contains(stopReason)
    }

    private func cleanText(from content: Any?, max length: Int) -> String? {
        let strings: [String]
        if let text = content as? String {
            strings = [text]
        } else if let blocks = content as? [Any] {
            strings = blocks.compactMap { block in
                guard let object = block as? [String: Any],
                      normalized(object["type"] as? String) == "text" else { return nil }
                return object["text"] as? String
            }
        } else {
            return nil
        }

        let visible = strings.compactMap(stripInternalBlocks).joined(separator: " ")
        let result = clean(visible, max: length)
        return result.isEmpty ? nil : result
    }

    private func stripInternalBlocks(_ value: String) -> String? {
        let blockNames = ["system-reminder", "local-command-caveat", "command-message", "command-name"]
        var result: [Substring] = []
        var hiddenBlock: String?

        for line in value.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentBlock = hiddenBlock {
                if trimmed.contains("</\(currentBlock)>") { hiddenBlock = nil }
                continue
            }
            if let name = blockNames.first(where: { trimmed.contains("<\($0)>") }) {
                if !trimmed.contains("</\(name)>") { hiddenBlock = name }
                continue
            }
            result.append(line)
        }
        let joined = result.joined(separator: " ")
        return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
    }

    private func clean(_ value: String, max length: Int) -> String {
        let oneLine = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>*_`- "))
        guard oneLine.count > length else { return oneLine }
        return String(oneLine.prefix(max(1, length - 1))) + "…"
    }

    private func projectName(from cwd: String) -> String? {
        let result = URL(fileURLWithPath: cwd).lastPathComponent
        return result.isEmpty ? nil : result
    }

    private func identifier(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= 80, !result.contains(where: \.isNewline) else { return nil }
        return result
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
