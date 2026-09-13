import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var compactMenuBar: Bool {
        didSet { defaults.set(compactMenuBar, forKey: Keys.compactMenuBar) }
    }
    @Published var hideIdleProviders: Bool {
        didSet { defaults.set(hideIdleProviders, forKey: Keys.hideIdleProviders) }
    }
    @Published var showProviderCardDetails: Bool {
        didSet { defaults.set(showProviderCardDetails, forKey: Keys.showProviderCardDetails) }
    }
    @Published var showProviderUsageBars: Bool {
        didSet { defaults.set(showProviderUsageBars, forKey: Keys.showProviderUsageBars) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published var deskDisplayEnabled: Bool {
        didSet { defaults.set(deskDisplayEnabled, forKey: Keys.deskDisplayEnabled) }
    }
    @Published var showDeskDisplayTitles: Bool {
        didSet { defaults.set(showDeskDisplayTitles, forKey: Keys.showDeskDisplayTitles) }
    }
    @Published var attentionAlertsEnabled: Bool {
        didSet { defaults.set(attentionAlertsEnabled, forKey: Keys.attentionAlertsEnabled) }
    }
    @Published var autoResumeAfterReset: Bool {
        didSet { defaults.set(autoResumeAfterReset, forKey: "autoResumeAfterReset") }
    }
    @Published private(set) var conversationLabels: [String: ConversationLabel]
    @Published private(set) var enabledProviders: Set<AIProvider>
    @Published private(set) var localProviderRoots: [AIProvider: [String]]

    private let defaults: UserDefaults

    private enum Keys {
        static let compactMenuBar = "compactMenuBar"
        static let hideIdleProviders = "hideIdleProviders"
        static let showProviderCardDetails = "showProviderCardDetails"
        static let showProviderUsageBars = "showProviderUsageBars"
        static let launchAtLogin = "launchAtLogin"
        static let enabledProviders = "authorizedLocalProviders.v1"
        static let deskDisplayEnabled = "deskDisplayEnabled"
        static let showDeskDisplayTitles = "showDeskDisplayTitles"
        static let attentionAlertsEnabled = "attentionAlertsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        conversationLabels = defaults.data(forKey: "conversationLabels.v1").flatMap { try? JSONDecoder().decode([String: ConversationLabel].self, from: $0) } ?? [:]
        let savedRoots = defaults.dictionary(forKey: "localProviderRoots.v1") as? [String: [String]] ?? [:]
        localProviderRoots = Dictionary(uniqueKeysWithValues: savedRoots.compactMap { key, paths in
            guard let provider = AIProvider(rawValue: key) else { return nil }
            return (provider, paths)
        })
        autoResumeAfterReset = defaults.bool(forKey: "autoResumeAfterReset")
        compactMenuBar = defaults.object(forKey: Keys.compactMenuBar) as? Bool ?? false
        hideIdleProviders = defaults.object(forKey: Keys.hideIdleProviders) as? Bool ?? false
        showProviderCardDetails = defaults.object(forKey: Keys.showProviderCardDetails) as? Bool ?? true
        showProviderUsageBars = defaults.object(forKey: Keys.showProviderUsageBars) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        deskDisplayEnabled = defaults.object(forKey: Keys.deskDisplayEnabled) as? Bool ?? false
        showDeskDisplayTitles = defaults.object(forKey: Keys.showDeskDisplayTitles) as? Bool ?? true
        attentionAlertsEnabled = defaults.object(forKey: Keys.attentionAlertsEnabled) as? Bool ?? false
        let saved = defaults.stringArray(forKey: Keys.enabledProviders)
        enabledProviders = saved.map { Set($0.compactMap(AIProvider.init(rawValue:))) } ?? []
    }

    func setLabel(name: String, folder: String, for session: AgentSession) {
        let key = "\(session.provider.rawValue):\(session.id)"
        let label = ConversationLabel(name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)), folder: String(folder.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))
        conversationLabels[key] = label.name.isEmpty && label.folder.isEmpty ? nil : label
        if let data = try? JSONEncoder().encode(conversationLabels) { defaults.set(data, forKey: "conversationLabels.v1") }
    }

    func presented(_ session: AgentSession) -> AgentSession {
        guard let label = conversationLabels["\(session.provider.rawValue):\(session.id)"] else { return session }
        var result = session
        if !label.name.isEmpty { result.title = label.name }
        if !label.folder.isEmpty { result.project = label.folder }
        return result
    }

    func isEnabled(_ provider: AIProvider) -> Bool { enabledProviders.contains(provider) }

    func roots(for provider: AIProvider) -> [String] { localProviderRoots[provider] ?? [] }

    func setLocalRoot(_ path: String, for provider: AIProvider) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        localProviderRoots[provider] = [trimmed]
        defaults.set(Dictionary(uniqueKeysWithValues: localProviderRoots.map { ($0.key.rawValue, $0.value) }), forKey: "localProviderRoots.v1")
    }

    func addLocalRoot(_ path: String, for provider: AIProvider) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var roots = localProviderRoots[provider] ?? []
        guard !roots.contains(trimmed) else { return }
        roots.append(trimmed)
        localProviderRoots[provider] = roots
        defaults.set(Dictionary(uniqueKeysWithValues: localProviderRoots.map { ($0.key.rawValue, $0.value) }), forKey: "localProviderRoots.v1")
    }

    func clearLocalRoots(for provider: AIProvider) {
        localProviderRoots.removeValue(forKey: provider)
        defaults.set(Dictionary(uniqueKeysWithValues: localProviderRoots.map { ($0.key.rawValue, $0.value) }), forKey: "localProviderRoots.v1")
    }

    func setEnabled(_ enabled: Bool, for provider: AIProvider) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
        defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Keys.enabledProviders)
    }
}

struct ConversationLabel: Codable, Equatable { let name: String; let folder: String }
