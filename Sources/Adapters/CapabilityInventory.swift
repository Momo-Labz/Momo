import Foundation

enum InstalledCapabilityKind: String, CaseIterable, Hashable, Sendable {
    case mcpServer
    case plugin
    case skill

    var label: String {
        switch self {
        case .mcpServer: return "MCP"
        case .plugin: return "PLUGIN"
        case .skill: return "SKILL"
        }
    }
}

enum CapabilityProvider: String, CaseIterable, Hashable, Sendable {
    case codex
    case claude
    case gemini
    case cursor
    case grok

    init(_ provider: AIProvider) {
        switch provider {
        case .codex: self = .codex
        case .claude: self = .claude
        case .gemini: self = .gemini
        case .cursor: self = .cursor
        case .grok: self = .grok
        }
    }
}

enum CapabilityOwner: Hashable, Sendable {
    case provider(CapabilityProvider)
    case shared
}

struct InstalledCapability: Identifiable, Hashable, Sendable {
    let name: String
    let kind: InstalledCapabilityKind
    let owners: Set<CapabilityOwner>
    let marketplaces: Set<String>
    let usedBy: Set<CapabilityProvider>

    var id: String { "\(kind.rawValue):\(name.lowercased())" }
    var isUsed: Bool { !usedBy.isEmpty }
    var isShared: Bool { owners.contains(.shared) }
    var providerOwners: Set<CapabilityProvider> {
        Set(owners.compactMap { owner in
            guard case let .provider(provider) = owner else { return nil }
            return provider
        })
    }

    func wasUsed(by provider: AIProvider) -> Bool {
        usedBy.contains(CapabilityProvider(provider))
    }
}

struct CapabilityMarketplace: Identifiable, Hashable, Sendable {
    let name: String
    let owners: Set<CapabilityOwner>

    var id: String { name.lowercased() }
    var providerOwners: Set<CapabilityProvider> {
        Set(owners.compactMap { owner in
            guard case let .provider(provider) = owner else { return nil }
            return provider
        })
    }
}

struct CapabilityInventory: Hashable, Sendable {
    let items: [InstalledCapability]
    let marketplaces: [CapabilityMarketplace]

    static let empty = CapabilityInventory(items: [], marketplaces: [])

    func items(of kind: InstalledCapabilityKind) -> [InstalledCapability] {
        items.filter { $0.kind == kind }
    }

    /// Returns installed inventory annotated with provenance from the supplied sessions.
    /// Session-only names are intentionally not inserted: the UI distinguishes installed
    /// inventory from capabilities that merely appeared in a transcript.
    func markingUsed(by sessions: [AgentSession]) -> CapabilityInventory {
        var usage: [CapabilityKey: Set<CapabilityProvider>] = [:]

        for session in sessions {
            let provider = CapabilityProvider(session.provider)
            for name in session.mcpServers {
                usage[CapabilityKey(kind: .mcpServer, name: name), default: []].insert(provider)
            }
            for name in session.skills {
                usage[CapabilityKey(kind: .skill, name: name), default: []].insert(provider)

                // Namespaced skills such as `plugin-name:skill-name` also prove that the
                // installed plugin was involved, without inventing a separate plugin entry.
                if let separator = name.firstIndex(of: ":") {
                    let plugin = String(name[..<separator])
                    usage[CapabilityKey(kind: .plugin, name: plugin), default: []].insert(provider)
                }
            }
            for name in session.plugins {
                usage[CapabilityKey(kind: .plugin, name: name), default: []].insert(provider)
            }
        }

        let marked = items.map { item in
            InstalledCapability(
                name: item.name,
                kind: item.kind,
                owners: item.owners,
                marketplaces: item.marketplaces,
                usedBy: usage[CapabilityKey(kind: item.kind, name: item.name)] ?? []
            )
        }
        return CapabilityInventory(items: marked, marketplaces: marketplaces)
    }
}

/// Reads local capability metadata without exposing command lines, environment variables,
/// credentials, project paths, or any other configuration values.
struct CapabilityInventoryReader: Sendable {
    let homeURL: URL

    init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeURL = homeURL.standardizedFileURL
    }

    func read(enabledProviders: Set<AIProvider> = Set(AIProvider.allCases)) -> CapabilityInventory {
        var accumulator = InventoryAccumulator()
        if enabledProviders.contains(.claude) {
            readClaudeConfig(into: &accumulator)
            readClaudePlugins(into: &accumulator)
        }
        readSkillDirectories(
            includeClaude: enabledProviders.contains(.claude),
            into: &accumulator
        )
        if enabledProviders.contains(.codex) { readCodexConfig(into: &accumulator) }
        if enabledProviders.contains(.cursor) { readCursorConfig(into: &accumulator) }
        return accumulator.inventory
    }

    private func readClaudeConfig(into accumulator: inout InventoryAccumulator) {
        guard let root = jsonDictionary(at: homeURL.appendingPathComponent(".claude.json")) else { return }
        let owner = CapabilityOwner.provider(.claude)

        addDictionaryKeys(root["mcpServers"], kind: .mcpServer, owner: owner, to: &accumulator)
        guard let projects = root["projects"] as? [String: Any] else { return }

        for value in projects.values {
            guard let project = value as? [String: Any] else { continue }
            addDictionaryKeys(project["mcpServers"], kind: .mcpServer, owner: owner, to: &accumulator)
            for key in ["enabledMcpjsonServers", "disabledMcpjsonServers"] {
                guard let names = project[key] as? [Any] else { continue }
                for case let name as String in names {
                    accumulator.add(name: name, kind: .mcpServer, owner: owner)
                }
            }
            guard let allowedTools = project["allowedTools"] as? [Any] else { continue }
            for case let tool as String in allowedTools {
                if let server = mcpServerName(from: tool) {
                    accumulator.add(name: server, kind: .mcpServer, owner: owner)
                }
            }
        }
    }

    private func readClaudePlugins(into accumulator: inout InventoryAccumulator) {
        let owner = CapabilityOwner.provider(.claude)
        let pluginURL = homeURL.appendingPathComponent(".claude/plugins/installed_plugins.json")
        if let root = jsonDictionary(at: pluginURL),
           let plugins = root["plugins"] as? [String: Any] {
            for identifier in plugins.keys {
                let parts = pluginIdentifier(identifier)
                accumulator.add(
                    name: parts.name,
                    kind: .plugin,
                    owner: owner,
                    marketplace: parts.marketplace
                )
            }
        }

        let marketplaceURL = homeURL.appendingPathComponent(".claude/plugins/known_marketplaces.json")
        if let root = jsonDictionary(at: marketplaceURL) {
            let marketplaces = root["marketplaces"] as? [String: Any] ?? root
            for name in marketplaces.keys {
                accumulator.addMarketplace(name: name, owner: owner)
            }
        }
    }

    private func readSkillDirectories(
        includeClaude: Bool,
        into accumulator: inout InventoryAccumulator
    ) {
        if includeClaude {
            addSkills(
                at: homeURL.appendingPathComponent(".claude/skills", isDirectory: true),
                owner: .provider(.claude),
                to: &accumulator
            )
        }
        addSkills(
            at: homeURL.appendingPathComponent(".agents/skills", isDirectory: true),
            owner: .shared,
            to: &accumulator
        )
    }

    private func readCodexConfig(into accumulator: inout InventoryAccumulator) {
        let url = homeURL.appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let owner = CapabilityOwner.provider(.codex)

        for rawLine in text.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let name = tomlSectionName(in: line, root: "mcp_servers") {
                accumulator.add(name: name, kind: .mcpServer, owner: owner)
            } else if let identifier = tomlSectionName(in: line, root: "plugins") {
                let parts = pluginIdentifier(identifier)
                accumulator.add(
                    name: parts.name,
                    kind: .plugin,
                    owner: owner,
                    marketplace: parts.marketplace
                )
            } else if let name = tomlSectionName(in: line, root: "marketplaces") {
                accumulator.addMarketplace(name: name, owner: owner)
            }
        }
    }

    private func readCursorConfig(into accumulator: inout InventoryAccumulator) {
        let url = homeURL.appendingPathComponent(".cursor/mcp.json")
        guard let root = jsonDictionary(at: url) else { return }
        addDictionaryKeys(
            root["mcpServers"],
            kind: .mcpServer,
            owner: .provider(.cursor),
            to: &accumulator
        )
    }

    private func addSkills(
        at directory: URL,
        owner: CapabilityOwner,
        to accumulator: inout InventoryAccumulator
    ) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            accumulator.add(name: entry.lastPathComponent, kind: .skill, owner: owner)
        }
    }

    private func addDictionaryKeys(
        _ value: Any?,
        kind: InstalledCapabilityKind,
        owner: CapabilityOwner,
        to accumulator: inout InventoryAccumulator
    ) {
        guard let dictionary = value as? [String: Any] else { return }
        for name in dictionary.keys {
            accumulator.add(name: name, kind: kind, owner: owner)
        }
    }

    private func jsonDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private func mcpServerName(from tool: String) -> String? {
        guard tool.hasPrefix("mcp__") else { return nil }
        let suffix = tool.dropFirst("mcp__".count)
        guard let separator = suffix.range(of: "__") else { return nil }
        return sanitizedName(String(suffix[..<separator.lowerBound]))
    }

    private func pluginIdentifier(_ identifier: String) -> (name: String, marketplace: String?) {
        guard let separator = identifier.lastIndex(of: "@") else {
            return (identifier, nil)
        }
        let name = String(identifier[..<separator])
        let marketplace = String(identifier[identifier.index(after: separator)...])
        return (name, sanitizedName(marketplace))
    }

    private func tomlSectionName(in line: String, root: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
        let inner = line.dropFirst().dropLast()
        let prefix = root + "."
        guard inner.hasPrefix(prefix) else { return nil }

        let remainder = inner.dropFirst(prefix.count)
        guard !remainder.isEmpty else { return nil }
        if remainder.first == "\"" {
            var escaped = false
            var result = ""
            for character in remainder.dropFirst() {
                if escaped {
                    result.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    return sanitizedName(result)
                } else {
                    result.append(character)
                }
            }
            return nil
        }

        let component = remainder.prefix { $0 != "." }
        return sanitizedName(String(component))
    }
}

private struct CapabilityKey: Hashable {
    let kind: InstalledCapabilityKind
    let normalizedName: String

    init(kind: InstalledCapabilityKind, name: String) {
        self.kind = kind
        normalizedName = normalizedCapabilityName(name)
    }
}

private struct InventoryAccumulator {
    private struct ItemValue {
        var name: String
        var owners: Set<CapabilityOwner> = []
        var marketplaces: Set<String> = []
    }

    private struct MarketplaceValue {
        var name: String
        var owners: Set<CapabilityOwner> = []
    }

    private var items: [CapabilityKey: ItemValue] = [:]
    private var marketplaceValues: [String: MarketplaceValue] = [:]

    mutating func add(
        name rawName: String,
        kind: InstalledCapabilityKind,
        owner: CapabilityOwner,
        marketplace: String? = nil
    ) {
        guard let name = sanitizedName(rawName) else { return }
        let key = CapabilityKey(kind: kind, name: name)
        var value = items[key] ?? ItemValue(name: name)
        value.owners.insert(owner)
        if let marketplace { value.marketplaces.insert(marketplace) }
        items[key] = value
    }

    mutating func addMarketplace(name rawName: String, owner: CapabilityOwner) {
        guard let name = sanitizedName(rawName) else { return }
        let key = normalizedCapabilityName(name)
        var value = marketplaceValues[key] ?? MarketplaceValue(name: name)
        value.owners.insert(owner)
        marketplaceValues[key] = value
    }

    var inventory: CapabilityInventory {
        let sortedItems = items.map { key, value in
            InstalledCapability(
                name: value.name,
                kind: key.kind,
                owners: value.owners,
                marketplaces: value.marketplaces,
                usedBy: []
            )
        }.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let sortedMarketplaces = marketplaceValues.values.map {
            CapabilityMarketplace(name: $0.name, owners: $0.owners)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return CapabilityInventory(items: sortedItems, marketplaces: sortedMarketplaces)
    }
}

private func sanitizedName(_ rawValue: String) -> String? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 128, !value.contains("\n"), !value.contains("\r") else { return nil }
    return value
}

private func normalizedCapabilityName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
