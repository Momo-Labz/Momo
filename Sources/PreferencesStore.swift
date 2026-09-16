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
    @Published var refreshIntervalSeconds: Int {
        didSet { defaults.set(Self.normalizedRefreshInterval(refreshIntervalSeconds), forKey: Keys.refreshIntervalSeconds) }
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
    /// Providers the person explicitly allowed for the tracking strip, usage peek, and Connect Usage queue.
    /// Separate from `enabledProviders` (local session-folder authorization).
    @Published private(set) var allowedTrackingProviders: Set<AIProvider>
    @Published private(set) var trackingOnboardingSeen: Bool
    /// First-run intents that emphasize Usage vs Brain tips without inventing features.
    @Published private(set) var onboardingIntents: Set<OnboardingIntent>
    @Published private(set) var localProviderRoots: [AIProvider: [String]]
    /// True until the current onboarding schema finishes (Welcome → prefs → Talk trial).
    var needsTrackingOnboarding: Bool { !trackingOnboardingSeen }

    /// Bump when the required onboarding steps change so legacy installs re-run once.
    static let currentOnboardingSchemaVersion = 2

    private let defaults: UserDefaults

    private enum Keys {
        static let compactMenuBar = "compactMenuBar"
        static let hideIdleProviders = "hideIdleProviders"
        static let showProviderCardDetails = "showProviderCardDetails"
        static let showProviderUsageBars = "showProviderUsageBars"
        static let launchAtLogin = "launchAtLogin"
        static let enabledProviders = "authorizedLocalProviders.v1"
        static let allowedTrackingProviders = "allowedTrackingProviders.v1"
        static let trackingOnboardingSeen = "trackingOnboardingSeen.v1"
        static let trackingOnboardingComplete = "trackingOnboardingComplete.v2"
        static let trackingOnboardingSchemaVersion = "trackingOnboardingSchemaVersion.v1"
        static let onboardingIntents = "onboardingIntents.v1"
        static let deskDisplayEnabled = "deskDisplayEnabled"
        static let showDeskDisplayTitles = "showDeskDisplayTitles"
        static let attentionAlertsEnabled = "attentionAlertsEnabled"
        static let refreshIntervalSeconds = "refreshIntervalSeconds.v1"
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
        refreshIntervalSeconds = Self.normalizedRefreshInterval(defaults.integer(forKey: Keys.refreshIntervalSeconds))
        deskDisplayEnabled = defaults.object(forKey: Keys.deskDisplayEnabled) as? Bool ?? false
        showDeskDisplayTitles = defaults.object(forKey: Keys.showDeskDisplayTitles) as? Bool ?? true
        attentionAlertsEnabled = defaults.object(forKey: Keys.attentionAlertsEnabled) as? Bool ?? false
        let saved = defaults.stringArray(forKey: Keys.enabledProviders)
        enabledProviders = saved.map { Set($0.compactMap(AIProvider.init(rawValue:))) } ?? []
        let savedAllowed = defaults.stringArray(forKey: Keys.allowedTrackingProviders)
        allowedTrackingProviders = savedAllowed.map { Set($0.compactMap(AIProvider.init(rawValue:))) } ?? []
        let savedSchema = defaults.integer(forKey: Keys.trackingOnboardingSchemaVersion)
        let legacySeen = defaults.bool(forKey: Keys.trackingOnboardingSeen)
        let completeV2 = defaults.bool(forKey: Keys.trackingOnboardingComplete)
        if savedSchema < Self.currentOnboardingSchemaVersion {
            // Legacy `trackingOnboardingSeen.v1` without prefs/Talk steps — force one full re-run.
            trackingOnboardingSeen = false
            defaults.set(false, forKey: Keys.trackingOnboardingComplete)
        } else {
            trackingOnboardingSeen = completeV2 || legacySeen
        }
        let savedIntents = defaults.stringArray(forKey: Keys.onboardingIntents) ?? []
        onboardingIntents = Set(savedIntents.compactMap(OnboardingIntent.init(rawValue:)))
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

    func isTrackingAllowed(_ provider: AIProvider) -> Bool { allowedTrackingProviders.contains(provider) }

    /// Providers shown in the sticky strip and menu-bar usage peek after onboarding.
    func trackingStripProviders() -> [AIProvider] {
        ProviderStripLayout.visibleProviders(
            allowed: allowedTrackingProviders,
            onboardingSeen: trackingOnboardingSeen
        )
    }

    func prefersUsageTips() -> Bool { onboardingIntents.contains(.usageTracking) }

    func prefersBrainTips() -> Bool {
        onboardingIntents.contains(.organizingPrompts) || onboardingIntents.contains(.projectFolders)
    }

    func setOnboardingIntents(_ intents: Set<OnboardingIntent>) {
        onboardingIntents = intents
        defaults.set(intents.map(\.rawValue).sorted(), forKey: Keys.onboardingIntents)
    }

    func setTrackingAllowed(_ allowed: Bool, for provider: AIProvider) {
        if allowed { allowedTrackingProviders.insert(provider) } else { allowedTrackingProviders.remove(provider) }
        defaults.set(allowedTrackingProviders.map(\.rawValue).sorted(), forKey: Keys.allowedTrackingProviders)
    }

    func setAllowedTrackingProviders(_ providers: Set<AIProvider>, markOnboardingSeen: Bool = true) {
        allowedTrackingProviders = providers
        defaults.set(providers.map(\.rawValue).sorted(), forKey: Keys.allowedTrackingProviders)
        if markOnboardingSeen {
            markTrackingOnboardingSeen()
        }
    }

    func markTrackingOnboardingSeen() {
        trackingOnboardingSeen = true
        defaults.set(true, forKey: Keys.trackingOnboardingSeen)
        defaults.set(true, forKey: Keys.trackingOnboardingComplete)
        defaults.set(Self.currentOnboardingSchemaVersion, forKey: Keys.trackingOnboardingSchemaVersion)
    }

    func syncRefreshIntervalFromDefaults() {
        refreshIntervalSeconds = Self.normalizedRefreshInterval(defaults.integer(forKey: Keys.refreshIntervalSeconds))
    }

    /// Tester/Settings path: clear the first-run gate so Welcome shows again.
    func reopenTrackingOnboarding() {
        trackingOnboardingSeen = false
        defaults.set(false, forKey: Keys.trackingOnboardingSeen)
        defaults.set(false, forKey: Keys.trackingOnboardingComplete)
        NotificationCenter.default.post(
            name: .momoShowProviderChooser,
            object: nil,
            userInfo: ["step": TrackingOnboardingStep.welcome.rawValue, "force": true]
        )
    }

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

    static let refreshIntervalOptions = [60, 300, 600, 1_800]

    static func normalizedRefreshInterval(_ seconds: Int) -> Int {
        refreshIntervalOptions.contains(seconds) ? seconds : 60
    }
}

struct ConversationLabel: Codable, Equatable { let name: String; let folder: String }
