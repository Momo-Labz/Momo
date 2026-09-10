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
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published private(set) var enabledProviders: Set<AIProvider>

    private let defaults: UserDefaults

    private enum Keys {
        static let compactMenuBar = "compactMenuBar"
        static let hideIdleProviders = "hideIdleProviders"
        static let launchAtLogin = "launchAtLogin"
        static let enabledProviders = "enabledProviders"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        compactMenuBar = defaults.object(forKey: Keys.compactMenuBar) as? Bool ?? false
        hideIdleProviders = defaults.object(forKey: Keys.hideIdleProviders) as? Bool ?? false
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        let saved = defaults.stringArray(forKey: Keys.enabledProviders)
        enabledProviders = saved.map { Set($0.compactMap(AIProvider.init(rawValue:))) } ?? Set(AIProvider.allCases)
    }

    func isEnabled(_ provider: AIProvider) -> Bool { enabledProviders.contains(provider) }

    func setEnabled(_ enabled: Bool, for provider: AIProvider) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
        defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Keys.enabledProviders)
    }
}

