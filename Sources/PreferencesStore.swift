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
    /// Providers the person explicitly allowed for the tracking strip after desktop-app connect.
    /// Separate from `enabledProviders` (local session-folder authorization).
    @Published private(set) var allowedTrackingProviders: Set<AIProvider>
    @Published private(set) var trackingOnboardingSeen: Bool
    /// First-run intents that emphasize Usage vs Brain tips without inventing features.
    @Published private(set) var onboardingIntents: Set<OnboardingIntent>
    @Published private(set) var localProviderRoots: [AIProvider: [String]]

    /// Incomplete installs always force Welcome → intents → verified connect.
    /// Empty allow-list never counts as finished, even if a legacy complete flag is set.
    /// Mid-flow TCC relaunch resumes via `onboardingResumeStep` when progress was persisted
    /// **and** onboarding is still incomplete — resume never skips a forced Welcome upgrade.
    var needsTrackingOnboarding: Bool {
        !trackingOnboardingSeen || allowedTrackingProviders.isEmpty
    }

    /// Bump when onboarding source changes.
    /// v6 = first force Welcome without Terminal wipe.
    /// v7 = re-force Welcome for installs that already wrote schema v6 complete from a broken/skipped run
    ///      (migration.v6 alone must not keep skipping Welcome).
    static let currentOnboardingSchemaVersion = 7
    static let freeProviderLimit = DesktopAppCatalog.freeProviderLimit

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
        static let trackingOnboardingComplete = "trackingOnboardingComplete.v7"
        static let trackingOnboardingSchemaVersion = "trackingOnboardingSchemaVersion.v1"
        /// Legacy one-time v6 wipe (kept so we can detect “already on v6” upgrades).
        static let onboardingMigrationV6 = "onboardingMigration.v6"
        /// One-time flag for the v7 Welcome re-force (no Terminal wipe).
        static let onboardingMigrationV7 = "onboardingMigration.v7"
        static let onboardingIntents = "onboardingIntents.v1"
        /// Persisted mid-flow step so TCC quit/relaunch resumes (not Welcome from scratch).
        static let onboardingResumeStep = "onboardingResumeStep.v1"
        static let onboardingPendingProvider = "onboardingPendingProvider.v1"
        static let onboardingPartialAllowed = "onboardingPartialAllowed.v1"
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
        let parsedAllowed = savedAllowed.map { Set($0.compactMap(AIProvider.init(rawValue:))) } ?? []
        let savedSchema = defaults.integer(forKey: Keys.trackingOnboardingSchemaVersion)
        let legacySeen = defaults.bool(forKey: Keys.trackingOnboardingSeen)
        let completeCurrent = defaults.bool(forKey: Keys.trackingOnboardingComplete)
        let savedIntents = defaults.stringArray(forKey: Keys.onboardingIntents) ?? []

        let migrationV7Applied = defaults.bool(forKey: Keys.onboardingMigrationV7)
        let resolvedAllowed: Set<AIProvider>
        let resolvedSeen: Bool
        if savedSchema < Self.currentOnboardingSchemaVersion || !migrationV7Applied {
            // Upgrade / first run of this build: force Welcome → connect without Terminal wipe.
            // Covers grok10/PR#5 installs that already wrote schema v6 + complete + allow-list
            // from a broken/skipped run — migration.v6 alone must not keep skipping Welcome.
            Self.clearOnboardingFlags(in: defaults)
            defaults.set([], forKey: Keys.allowedTrackingProviders)
            Self.clearOnboardingProgressKeys(in: defaults)
            defaults.set(true, forKey: Keys.onboardingMigrationV6)
            defaults.set(true, forKey: Keys.onboardingMigrationV7)
            defaults.set(Self.currentOnboardingSchemaVersion, forKey: Keys.trackingOnboardingSchemaVersion)
            resolvedAllowed = []
            resolvedSeen = false
        } else if parsedAllowed.isEmpty {
            // Schema current but no verified providers — never treat as finished.
            Self.clearOnboardingFlags(in: defaults)
            // Keep mid-flow resume keys so TCC relaunch can restore step when allow-list is still empty.
            resolvedAllowed = []
            resolvedSeen = false
        } else if completeCurrent || legacySeen {
            // Genuine finish after this build’s Finish path (v7 complete and/or seen).
            resolvedAllowed = parsedAllowed
            resolvedSeen = true
        } else {
            // Providers on the strip mid-flow, but Finish never ran — still needs onboarding.
            resolvedAllowed = parsedAllowed
            resolvedSeen = false
        }

        allowedTrackingProviders = resolvedAllowed
        trackingOnboardingSeen = resolvedSeen
        onboardingIntents = Set(savedIntents.compactMap(OnboardingIntent.init(rawValue:)))
    }

    /// Clears every known onboarding completion key (v2…v7) plus the seen flag.
    static func clearOnboardingFlags(in defaults: UserDefaults) {
        defaults.set(false, forKey: Keys.trackingOnboardingSeen)
        defaults.set(false, forKey: Keys.trackingOnboardingComplete)
        defaults.set(false, forKey: "trackingOnboardingComplete.v7")
        defaults.set(false, forKey: "trackingOnboardingComplete.v6")
        defaults.set(false, forKey: "trackingOnboardingComplete.v5")
        defaults.set(false, forKey: "trackingOnboardingComplete.v4")
        defaults.set(false, forKey: "trackingOnboardingComplete.v3")
        defaults.set(false, forKey: "trackingOnboardingComplete.v2")
    }

    static func clearOnboardingProgressKeys(in defaults: UserDefaults) {
        defaults.removeObject(forKey: Keys.onboardingResumeStep)
        defaults.removeObject(forKey: Keys.onboardingPendingProvider)
        defaults.removeObject(forKey: Keys.onboardingPartialAllowed)
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
        ProviderStripLayout.visibleProviders(allowed: allowedTrackingProviders)
    }

    /// Soft-lock: Free may allow at most `freeProviderLimit` providers unless MOMO+.
    func canAllowTrackingProvider(_ provider: AIProvider, momoPlus: Bool) -> Bool {
        if allowedTrackingProviders.contains(provider) { return true }
        if momoPlus { return true }
        return allowedTrackingProviders.count < Self.freeProviderLimit
    }

    /// Desktop-app connect: allow-list + enable local session scan for that provider.
    @discardableResult
    func connectDesktopProvider(_ provider: AIProvider, trackUsage: Bool, trackRecentPrompts: Bool, momoPlus: Bool) -> Bool {
        guard trackUsage || trackRecentPrompts else { return false }
        guard canAllowTrackingProvider(provider, momoPlus: momoPlus) else { return false }
        allowedTrackingProviders.insert(provider)
        defaults.set(allowedTrackingProviders.map(\.rawValue).sorted(), forKey: Keys.allowedTrackingProviders)
        setEnabled(true, for: provider)
        return true
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
        if allowedTrackingProviders.isEmpty {
            trackingOnboardingSeen = false
            Self.clearOnboardingFlags(in: defaults)
        }
    }

    func setAllowedTrackingProviders(_ providers: Set<AIProvider>, markOnboardingSeen: Bool = true) {
        allowedTrackingProviders = providers
        defaults.set(providers.map(\.rawValue).sorted(), forKey: Keys.allowedTrackingProviders)
        if markOnboardingSeen {
            markTrackingOnboardingSeen()
        } else if providers.isEmpty {
            trackingOnboardingSeen = false
            Self.clearOnboardingFlags(in: defaults)
        }
    }

    /// Completes onboarding only when ≥1 provider is on the allow-list.
    func markTrackingOnboardingSeen() {
        guard !allowedTrackingProviders.isEmpty else {
            trackingOnboardingSeen = false
            Self.clearOnboardingFlags(in: defaults)
            return
        }
        trackingOnboardingSeen = true
        defaults.set(true, forKey: Keys.trackingOnboardingSeen)
        defaults.set(true, forKey: Keys.trackingOnboardingComplete)
        defaults.set(Self.currentOnboardingSchemaVersion, forKey: Keys.trackingOnboardingSchemaVersion)
        defaults.set(true, forKey: Keys.onboardingMigrationV6)
        defaults.set(true, forKey: Keys.onboardingMigrationV7)
        clearOnboardingProgress()
    }

    func syncRefreshIntervalFromDefaults() {
        refreshIntervalSeconds = Self.normalizedRefreshInterval(defaults.integer(forKey: Keys.refreshIntervalSeconds))
    }

    /// Persist mid-onboarding progress so mic/notifications TCC relaunch resumes the same step.
    func saveOnboardingProgress(
        step: TrackingOnboardingStep,
        intents: Set<OnboardingIntent>,
        partialAllowed: Set<AIProvider>,
        pendingProvider: AIProvider?
    ) {
        defaults.set(step.rawValue, forKey: Keys.onboardingResumeStep)
        setOnboardingIntents(intents)
        defaults.set(partialAllowed.map(\.rawValue).sorted(), forKey: Keys.onboardingPartialAllowed)
        if let pendingProvider {
            defaults.set(pendingProvider.rawValue, forKey: Keys.onboardingPendingProvider)
        } else {
            defaults.removeObject(forKey: Keys.onboardingPendingProvider)
        }
        // Keep allow-list in sync so strip + needsTrackingOnboarding stay honest mid-flow.
        if !partialAllowed.isEmpty {
            allowedTrackingProviders = partialAllowed
            defaults.set(partialAllowed.map(\.rawValue).sorted(), forKey: Keys.allowedTrackingProviders)
        }
    }

    func clearOnboardingProgress() {
        Self.clearOnboardingProgressKeys(in: defaults)
    }

    /// Step to resume after relaunch. Nil when finished, or when no in-progress checkpoint exists.
    /// Never used to skip a forced Welcome — callers only resume while `needsTrackingOnboarding`.
    func resumedOnboardingStep() -> TrackingOnboardingStep? {
        guard !trackingOnboardingSeen else { return nil }
        guard defaults.object(forKey: Keys.onboardingResumeStep) != nil else { return nil }
        return TrackingOnboardingStep(rawValue: defaults.integer(forKey: Keys.onboardingResumeStep))
    }

    func resumedOnboardingPartialAllowed() -> Set<AIProvider> {
        guard !trackingOnboardingSeen else { return [] }
        let saved = defaults.stringArray(forKey: Keys.onboardingPartialAllowed) ?? []
        let parsed = Set(saved.compactMap(AIProvider.init(rawValue:)))
        if !parsed.isEmpty { return parsed }
        return allowedTrackingProviders
    }

    func resumedOnboardingPendingProvider() -> AIProvider? {
        guard !trackingOnboardingSeen else { return nil }
        return defaults.string(forKey: Keys.onboardingPendingProvider).flatMap(AIProvider.init(rawValue:))
    }

    /// Tester/Settings path: clear the first-run gate so Welcome shows again.
    /// Preferred retest path — do not document Terminal `defaults delete` for shipping QA.
    func reopenTrackingOnboarding() {
        trackingOnboardingSeen = false
        allowedTrackingProviders = []
        Self.clearOnboardingFlags(in: defaults)
        defaults.set([], forKey: Keys.allowedTrackingProviders)
        clearOnboardingProgress()
        // Keep migration flags so Replay does not fight the one-time upgrade wipe.
        defaults.set(true, forKey: Keys.onboardingMigrationV6)
        defaults.set(true, forKey: Keys.onboardingMigrationV7)
        defaults.set(Self.currentOnboardingSchemaVersion, forKey: Keys.trackingOnboardingSchemaVersion)
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
