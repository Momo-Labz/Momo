import Foundation

/// Free Talk: 1 guided onboarding trial + 3 uses. Further asks require MOMO+.
/// Local-only counters — no StoreKit; Plus is a soft entitlement hook.
@MainActor
final class TalkQuotaStore: ObservableObject {
    static let freeUsesLimit = 3

    /// Upgrade / Talk gate copy — Plus framing: unlimited Talk, >2 providers, analytics.
    enum UpsellCopy {
        static let inline = "You’ve used your free Talk asks. MOMO+ unlocks unlimited Talk, more than 2 providers, and analytics — still local, still no invented quotas."
        static let primaryButton = "Continue with MOMO+"
        static let secondaryButton = "Not now"
        static let optionalOneLiner = "Free includes 1 guided Talk trial + 3 asks and up to 2 desktop providers."
        static let upgradeHeadline = "MOMO+"
        static let upgradePitch = "Track more of the AI apps you already run on this Mac. Unlimited Talk, more than 2 providers, and analytics — local-first, no invented quotas."
        static let benefitTalk = "Unlimited Talk (beyond 1 trial + 3 free asks)"
        static let benefitProviders = "More than 2 desktop providers"
        static let benefitAnalytics = "Analytics across connected apps"
    }

    enum Access: Equatable {
        case allowedOnboarding
        case allowedFree(remainingAfter: Int)
        case allowedPlus
        case requiresPlus
    }

    @Published private(set) var onboardingTalkUsed: Bool
    @Published private(set) var freeTalkUsesConsumed: Int
    @Published private(set) var momoPlusEntitled: Bool

    private let defaults: UserDefaults

    private enum Keys {
        static let onboardingTalkUsed = "talkOnboardingUsed.v1"
        static let freeTalkUsesConsumed = "talkFreeUsesConsumed.v1"
        static let momoPlusEntitled = "momoPlusEntitled.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingTalkUsed = defaults.bool(forKey: Keys.onboardingTalkUsed)
        freeTalkUsesConsumed = max(0, defaults.integer(forKey: Keys.freeTalkUsesConsumed))
        momoPlusEntitled = defaults.bool(forKey: Keys.momoPlusEntitled)
    }

    var freeUsesRemaining: Int {
        max(0, Self.freeUsesLimit - freeTalkUsesConsumed)
    }

    func access(isOnboardingTrial: Bool = false) -> Access {
        if momoPlusEntitled { return .allowedPlus }
        if isOnboardingTrial, !onboardingTalkUsed { return .allowedOnboarding }
        if freeTalkUsesConsumed < Self.freeUsesLimit {
            return .allowedFree(remainingAfter: Self.freeUsesLimit - freeTalkUsesConsumed - 1)
        }
        return .requiresPlus
    }

    @discardableResult
    func consume(isOnboardingTrial: Bool = false) -> Access {
        let gate = access(isOnboardingTrial: isOnboardingTrial)
        switch gate {
        case .allowedOnboarding:
            onboardingTalkUsed = true
            defaults.set(true, forKey: Keys.onboardingTalkUsed)
        case .allowedFree:
            freeTalkUsesConsumed += 1
            defaults.set(freeTalkUsesConsumed, forKey: Keys.freeTalkUsesConsumed)
        case .allowedPlus, .requiresPlus:
            break
        }
        return gate
    }

    func setMomoPlusEntitled(_ entitled: Bool) {
        momoPlusEntitled = entitled
        defaults.set(entitled, forKey: Keys.momoPlusEntitled)
    }

    /// Tester / Settings reset for free counters (does not clear Plus).
    func resetFreeQuotaForTesting() {
        onboardingTalkUsed = false
        freeTalkUsesConsumed = 0
        defaults.set(false, forKey: Keys.onboardingTalkUsed)
        defaults.set(0, forKey: Keys.freeTalkUsesConsumed)
    }
}
