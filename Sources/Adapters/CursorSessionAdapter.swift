import Foundation

/// Parses Cursor's text-only agent transcript schema.
///
/// Cursor does not record model identity, token usage, lifecycle events, or reliable
/// capability provenance in these JSONL files. Those values intentionally remain absent.
struct CursorSessionAdapter: ProviderSessionAdapter {
    let provider: AIProvider = .cursor

    func session(
        from file: ProviderSessionFile,
        context: ProviderSessionContext
    ) -> AgentSession? {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return nil }
        defer { try? handle.close() }

        var metadata = CursorSessionMetadata()
        forEachJSONLine(in: handle) { object in
            metadata.consume(object)
        }

        let isRunning = context.isLikelyRunning(file)
        return AgentSession(
            id: "cursor-\(file.url.path)",
            provider: provider,
            role: isSubagent(file.url) ? .subagent : .main,
            title: metadata.title ?? "Cursor session",
            detail: metadata.detail ?? "Recent Cursor transcript",
            project: projectName(from: file.url) ?? "Cursor",
            updatedAt: file.modifiedAt,
            isRunning: isRunning,
            processID: nil,
            tokens: nil,
            attention: isRunning ? .working : .idle,
            attentionReason: nil,
            model: nil,
            mcpServers: [],
            skills: [],
            plugins: []
        )
    }

    private func forEachJSONLine(
        in handle: FileHandle,
        consume: ([String: Any]) -> Void
    ) {
        var pending = Data()
        let newline = UInt8(ascii: "\n")

        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            while let boundary = pending.firstIndex(of: newline) {
                decode(pending[..<boundary], consume: consume)
                pending.removeSubrange(...boundary)
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

    private func isSubagent(_ url: URL) -> Bool {
        url.pathComponents.contains("subagents")
    }

    private func projectName(from url: URL) -> String? {
        let components = url.pathComponents
        guard let projectsIndex = components.lastIndex(of: "projects"),
              components.indices.contains(projectsIndex + 1) else { return nil }

        var slug = components[projectsIndex + 1]
        let homePrefix = FileManager.default.homeDirectoryForCurrentUser.pathComponents
            .filter { $0 != "/" }
            .joined(separator: "-") + "-"
        if slug.hasPrefix(homePrefix) {
            slug.removeFirst(homePrefix.count)
        }
        for container in ["Desktop-", "Documents-", "Developer-"] where slug.hasPrefix(container) {
            slug.removeFirst(container.count)
            break
        }

        let name = slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}

private struct CursorSessionMetadata {
    var title: String?
    var detail: String?

    mutating func consume(_ event: [String: Any]) {
        guard let role = nonemptyString(event["role"]),
              let message = event["message"] as? [String: Any],
              let text = visibleText(from: message["content"]) else { return }

        switch role.lowercased() {
        case "user":
            if title == nil { title = clean(text, max: 68) }
        case "assistant":
            detail = clean(text, max: 88)
        default:
            break
        }
    }

    private func visibleText(from content: Any?) -> String? {
        guard let blocks = content as? [Any] else { return nil }
        let values = blocks.compactMap { block -> String? in
            guard let object = block as? [String: Any],
                  normalized(object["type"] as? String) == "text",
                  let text = nonemptyString(object["text"]) else { return nil }
            return userQuery(in: text) ?? stripInternalBlocks(text)
        }
        let result = values.joined(separator: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
    }

    private func userQuery(in text: String) -> String? {
        guard let opening = text.range(of: "<user_query>"),
              let closing = text.range(of: "</user_query>", range: opening.upperBound..<text.endIndex) else {
            return nil
        }
        let value = String(text[opening.upperBound..<closing.lowerBound])
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func stripInternalBlocks(_ text: String) -> String {
        var result = text
        for name in ["timestamp", "system-reminder", "local-command-caveat", "command-message", "command-name"] {
            result = removingBlocks(named: name, from: result)
        }
        return result
    }

    private func removingBlocks(named name: String, from text: String) -> String {
        var result = text
        let opening = "<\(name)>"
        let closing = "</\(name)>"
        while let start = result.range(of: opening),
              let end = result.range(of: closing, range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result
    }

    private func clean(_ value: String, max length: Int) -> String {
        let oneLine = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>*_`- "))
        guard oneLine.count > length else { return oneLine }
        return String(oneLine.prefix(max(1, length - 1))) + "…"
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
