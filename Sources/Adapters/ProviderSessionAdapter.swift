import Foundation

/// A session file selected by `LocalActivityScanner` for provider-specific parsing.
struct ProviderSessionFile: Sendable {
    let url: URL
    let modifiedAt: Date
    let index: Int
}

/// Runtime facts shared with every provider adapter.
struct ProviderSessionContext: Sendable {
    let now: Date
    let isProviderRunning: Bool

    func isLikelyRunning(_ file: ProviderSessionFile) -> Bool {
        isProviderRunning && file.index == 0
    }
}

/// Converts one provider-owned transcript into MOMO's shared session model.
///
/// Adapters must report unavailable fields as `nil`; they must not manufacture usage,
/// model, provenance, or attention data that is absent from the provider's schema.
protocol ProviderSessionAdapter: Sendable {
    var provider: AIProvider { get }

    func session(
        from file: ProviderSessionFile,
        context: ProviderSessionContext
    ) -> AgentSession?
}

/// Scanner composition point. Provider-specific adapters replace only their provider's
/// generic fallback, so adapters can be introduced independently.
struct ProviderSessionAdapterRegistry: Sendable {
    private let adapters: [AIProvider: any ProviderSessionAdapter]

    init(overrides: [any ProviderSessionAdapter] = []) {
        var result: [AIProvider: any ProviderSessionAdapter] = Dictionary(
            uniqueKeysWithValues: AIProvider.allCases.map { provider in
                (provider, GenericProviderSessionAdapter(provider: provider))
            }
        )
        for adapter in overrides {
            result[adapter.provider] = adapter
        }
        adapters = result
    }

    func adapter(for provider: AIProvider) -> any ProviderSessionAdapter {
        // Every AIProvider case is installed above; this is intentionally total.
        adapters[provider]!
    }
}

/// Compatibility parser retained until a schema-specific adapter replaces it.
struct GenericProviderSessionAdapter: ProviderSessionAdapter {
    let provider: AIProvider

    func session(
        from file: ProviderSessionFile,
        context: ProviderSessionContext
    ) -> AgentSession? {
        let metadata = sessionMetadata(from: file.url)
        return AgentSession(
            id: "\(provider.rawValue)-\(file.url.path)",
            provider: provider,
            role: metadata.isSubagent ? .subagent : .main,
            title: metadata.title ?? humanized(file.url.deletingPathExtension().lastPathComponent),
            detail: metadata.detail ?? "Recent local session",
            project: metadata.project ?? humanized(file.url.deletingLastPathComponent().lastPathComponent),
            updatedAt: file.modifiedAt,
            isRunning: context.isLikelyRunning(file),
            processID: nil,
            tokens: metadata.tokens,
            attention: metadata.attention,
            attentionReason: metadata.attentionReason,
            model: metadata.capabilities.model,
            mcpServers: metadata.capabilities.mcpServers.sorted(),
            skills: metadata.capabilities.skills.sorted(),
            plugins: metadata.capabilities.plugins.sorted()
        )
    }

    private func sessionMetadata(from url: URL) -> SessionMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return SessionMetadata() }
        defer { try? handle.close() }

        let maxBytes = 320 * 1024
        let head = (try? handle.read(upToCount: maxBytes / 2)) ?? Data()
        let size = (try? handle.seekToEnd()) ?? 0
        if size > UInt64(maxBytes / 2) {
            try? handle.seek(toOffset: size - UInt64(maxBytes / 2))
        }
        let tail = (try? handle.read(upToCount: maxBytes / 2)) ?? Data()
        var data = head
        data.append(Data("\n".utf8))
        data.append(tail)
        guard let text = String(data: data, encoding: .utf8) else { return SessionMetadata() }

        var metadata = SessionMetadata()
        var tokens = 0
        for line in text.split(separator: "\n").suffix(500) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if metadata.project == nil {
                metadata.project = findString(in: object, keys: ["cwd", "project_path"])
                    .map { URL(fileURLWithPath: $0).lastPathComponent }
            }
            if metadata.title == nil,
               let candidate = findString(in: object, keys: ["objective", "prompt", "task", "user_message"]) {
                metadata.title = clean(candidate, max: 68)
            }
            if metadata.detail == nil,
               let candidate = findString(in: object, keys: ["message", "summary", "last_message"]) {
                metadata.detail = clean(candidate, max: 88)
            }
            tokens = max(tokens, findInt(in: object, keys: ["total_tokens", "tokens_used", "input_tokens", "output_tokens"]) ?? 0)
            if let role = findString(in: object, keys: ["role", "agent_role", "agent_type"])?.lowercased(),
               role.contains("sub") {
                metadata.isSubagent = true
            }
            if let signal = attentionSignal(in: object) {
                metadata.attention = signal.state
                metadata.attentionReason = signal.reason
            }
            metadata.capabilities.merge(SessionCapabilities.infer(from: object))
        }
        metadata.tokens = tokens == 0 ? nil : tokens
        return metadata
    }

    private func attentionSignal(in object: [String: Any]) -> (state: AgentAttention, reason: String)? {
        let type = findString(in: object, keys: ["type", "event", "event_type", "status", "state"])?.lowercased() ?? ""
        let explicitNeedsInput = ["approval_request", "request_user_input", "requires_action", "waiting_for_user", "needs_input"]
        if explicitNeedsInput.contains(where: { type.contains($0) }) {
            return (.needsInput, "The agent is waiting for your response")
        }
        if ["failed", "error", "cancelled"].contains(where: { type == $0 || type.hasSuffix("_\($0)") }) {
            return (.failed, "The latest agent event failed")
        }
        if ["completed", "complete", "finished", "done"].contains(type) {
            return (.completed, "The latest task finished")
        }
        return nil
    }

    private func findString(in value: Any, keys: Set<String>) -> String? {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if keys.contains(key),
                   let text = child as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                if let found = findString(in: child, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findString(in: child, keys: keys) { return found }
            }
        }
        return nil
    }

    private func findInt(in value: Any, keys: Set<String>) -> Int? {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if keys.contains(key), let number = child as? NSNumber { return number.intValue }
                if let found = findInt(in: child, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findInt(in: child, keys: keys) { return found }
            }
        }
        return nil
    }

    private func humanized(_ value: String) -> String {
        let replaced = value.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return replaced.isEmpty ? "Untitled" : replaced.capitalized
    }

    private func clean(_ value: String, max length: Int) -> String {
        let oneLine = value.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return oneLine.count > length ? String(oneLine.prefix(length - 1)) + "…" : oneLine
    }
}

private struct SessionMetadata {
    var title: String?
    var detail: String?
    var project: String?
    var tokens: Int?
    var isSubagent = false
    var attention: AgentAttention = .working
    var attentionReason: String?
    var capabilities = SessionCapabilities()
}
