import Foundation
import XCTest
@testable import BAR_BOY

@MainActor
final class OnboardingAndTalkTests: XCTestCase {
    func testLegacyOnboardingSeenWithoutSchemaForcesRerun() {
        let suite = UserDefaults(suiteName: "MomoOnboardingMigrate.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        suite.set(true, forKey: "trackingOnboardingSeen.v1")
        suite.set([AIProvider.codex.rawValue, AIProvider.claude.rawValue], forKey: "allowedTrackingProviders.v1")
        suite.set(2, forKey: "trackingOnboardingSchemaVersion.v1")
        suite.set(true, forKey: "trackingOnboardingComplete.v2")
        XCTAssertEqual(suite.integer(forKey: "trackingOnboardingSchemaVersion.v1"), 2)

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertFalse(preferences.trackingOnboardingSeen)
        XCTAssertTrue(preferences.allowedTrackingProviders.isEmpty)

        preferences.setAllowedTrackingProviders([.codex], markOnboardingSeen: true)
        XCTAssertFalse(preferences.needsTrackingOnboarding)
        XCTAssertEqual(suite.integer(forKey: "trackingOnboardingSchemaVersion.v1"), PreferencesStore.currentOnboardingSchemaVersion)
        XCTAssertTrue(suite.bool(forKey: "trackingOnboardingComplete.v6"))
    }

    func testSchemaV6ClearsV5CompleteAndEmptyAllowListNeverFinishes() {
        let suite = UserDefaults(suiteName: "MomoSchemaV6.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        suite.set(true, forKey: "trackingOnboardingSeen.v1")
        suite.set(5, forKey: "trackingOnboardingSchemaVersion.v1")
        suite.set(true, forKey: "trackingOnboardingComplete.v5")
        suite.set([], forKey: "allowedTrackingProviders.v1")

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertEqual(PreferencesStore.currentOnboardingSchemaVersion, 6)
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertFalse(preferences.trackingOnboardingSeen)
        XCTAssertTrue(preferences.allowedTrackingProviders.isEmpty)
        XCTAssertTrue(suite.bool(forKey: "onboardingMigration.v6"))

        // Marking complete without providers must not stick.
        preferences.markTrackingOnboardingSeen()
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertFalse(preferences.trackingOnboardingSeen)
    }

    func testCompletedV5WithProvidersStillForcedBySchemaV6() {
        let suite = UserDefaults(suiteName: "MomoSchemaV6Providers.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        suite.set(true, forKey: "trackingOnboardingSeen.v1")
        suite.set(5, forKey: "trackingOnboardingSchemaVersion.v1")
        suite.set(true, forKey: "trackingOnboardingComplete.v5")
        suite.set([AIProvider.codex.rawValue], forKey: "allowedTrackingProviders.v1")

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertTrue(preferences.allowedTrackingProviders.isEmpty)
        XCTAssertTrue(suite.bool(forKey: "onboardingMigration.v6"))
    }

    func testMigrationFlagPreventsRepeatWipeAfterComplete() {
        let suite = UserDefaults(suiteName: "MomoSchemaV6Stable.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let first = PreferencesStore(defaults: suite)
        XCTAssertTrue(first.needsTrackingOnboarding)
        first.setAllowedTrackingProviders([.claude], markOnboardingSeen: true)
        XCTAssertFalse(first.needsTrackingOnboarding)

        let second = PreferencesStore(defaults: suite)
        XCTAssertFalse(second.needsTrackingOnboarding)
        XCTAssertEqual(second.allowedTrackingProviders, [.claude])
    }

    func testFreeProviderSoftLockAndDesktopConnect() {
        let suite = UserDefaults(suiteName: "MomoProviderLock.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertTrue(preferences.connectDesktopProvider(.codex, trackUsage: true, trackRecentPrompts: true, momoPlus: false))
        XCTAssertTrue(preferences.connectDesktopProvider(.claude, trackUsage: true, trackRecentPrompts: false, momoPlus: false))
        XCTAssertFalse(preferences.connectDesktopProvider(.cursor, trackUsage: true, trackRecentPrompts: true, momoPlus: false))
        XCTAssertEqual(preferences.allowedTrackingProviders, [.codex, .claude])
        XCTAssertTrue(preferences.isEnabled(.codex))
        XCTAssertTrue(preferences.connectDesktopProvider(.cursor, trackUsage: true, trackRecentPrompts: true, momoPlus: true))
        XCTAssertEqual(DesktopAppCatalog.freeProviderLimit, 2)
    }

    func testFirstRunOnboardingGateAndReplay() {
        let suite = UserDefaults(suiteName: "MomoOnboardingGate.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertFalse(preferences.trackingOnboardingSeen)
        XCTAssertEqual(preferences.trackingStripProviders(), [])

        preferences.setOnboardingIntents([.usageTracking])
        preferences.setAllowedTrackingProviders([.codex, .claude], markOnboardingSeen: true)
        XCTAssertFalse(preferences.needsTrackingOnboarding)
        XCTAssertEqual(preferences.trackingStripProviders(), [.codex, .claude])

        preferences.reopenTrackingOnboarding()
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertFalse(preferences.trackingOnboardingSeen)
        // Replay clears allow-list so connect starts empty again.
        XCTAssertTrue(preferences.allowedTrackingProviders.isEmpty)
        XCTAssertEqual(preferences.trackingStripProviders(), [])
    }

    func testAllowListStripEqualFlexibleWidths() {
        XCTAssertEqual(
            ProviderStripLayout.visibleProviders(allowed: [.codex, .gemini, .grok], onboardingSeen: true),
            [.codex, .gemini, .grok]
        )
        let width = try XCTUnwrap(ProviderStripLayout.equalCardWidth(availableWidth: 414, count: 3, spacing: 7))
        XCTAssertEqual(width, (414 - 14) / 3, accuracy: 0.001)
        let solo = try XCTUnwrap(ProviderStripLayout.equalCardWidth(availableWidth: 414, count: 1))
        XCTAssertEqual(solo, 414, accuracy: 0.001)
    }

    func testTalkFreeQuotaOnboardingPlusThreeThenUpsell() {
        let suite = UserDefaults(suiteName: "MomoTalkQuota.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let quota = TalkQuotaStore(defaults: suite)
        XCTAssertEqual(quota.access(isOnboardingTrial: true), .allowedOnboarding)
        XCTAssertEqual(quota.consume(isOnboardingTrial: true), .allowedOnboarding)
        XCTAssertTrue(quota.onboardingTalkUsed)
        XCTAssertEqual(quota.freeUsesRemaining, 3)

        XCTAssertEqual(quota.access(isOnboardingTrial: true), .allowedFree(remainingAfter: 2))
        for expectedRemaining in [2, 1, 0] {
            let gate = quota.consume()
            guard case .allowedFree(let remaining) = gate else {
                return XCTFail("Expected free access, got \(gate)")
            }
            XCTAssertEqual(remaining, expectedRemaining)
        }
        XCTAssertEqual(quota.access(), .requiresPlus)
        XCTAssertEqual(TalkQuotaStore.UpsellCopy.inline, "You’ve used your free Talk asks. MOMO+ unlocks unlimited Talk, more than 2 providers, and analytics — still local, still no invented quotas.")
        XCTAssertEqual(TalkQuotaStore.UpsellCopy.primaryButton, "Continue with MOMO+")
        XCTAssertEqual(TalkQuotaStore.UpsellCopy.secondaryButton, "Not now")
        XCTAssertEqual(
            TalkQuotaStore.UpsellCopy.optionalOneLiner,
            "Free includes 1 guided Talk trial + 3 asks and up to 2 desktop providers."
        )

        quota.setMomoPlusEntitled(true)
        XCTAssertEqual(quota.access(), .allowedPlus)

        let reloaded = TalkQuotaStore(defaults: suite)
        XCTAssertTrue(reloaded.onboardingTalkUsed)
        XCTAssertEqual(reloaded.freeTalkUsesConsumed, 3)
        XCTAssertTrue(reloaded.momoPlusEntitled)
    }

    func testAlertSoundPreferencePersists() {
        let suite = UserDefaults(suiteName: "MomoAlertSound.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let presenter = MomoAlertPresenter(defaults: suite)
        XCTAssertTrue(presenter.soundEnabled)
        XCTAssertFalse(presenter.muted)
        XCTAssertEqual(presenter.soundName, "Sosumi")

        presenter.soundEnabled = false
        presenter.muted = true
        presenter.soundName = "Glass"

        let reloaded = MomoAlertPresenter(defaults: suite)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertTrue(reloaded.muted)
        XCTAssertEqual(reloaded.soundName, "Glass")
    }

    func testTalkFactsNeverInventPercentages() {
        let snapshot = ProviderSnapshot(
            provider: .codex,
            sessions: [
                AgentSession(
                    id: "1",
                    provider: .codex,
                    role: .main,
                    title: "backend for Nibblr",
                    detail: "",
                    project: "Nibblr",
                    updatedAt: .now,
                    isRunning: true,
                    processID: 42,
                    tokens: nil,
                    attention: .working
                )
            ],
            activeCount: 1,
            localTokensToday: 0,
            updatedAt: .now,
            isInstalled: true
        )
        let facts = TalkService.factsBlock(
            snapshots: [snapshot],
            observations: [],
            allowed: [.codex]
        )
        XCTAssertTrue(facts.contains("verified usage %: unknown"))
        XCTAssertTrue(facts.contains("backend for Nibblr"))
        XCTAssertFalse(facts.contains("38%"))
    }

    func testRefreshIntervalNormalizationAndPersistence() {
        let suite = UserDefaults(suiteName: "MomoRefresh.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertEqual(preferences.refreshIntervalSeconds, 60)
        preferences.refreshIntervalSeconds = 600
        XCTAssertEqual(preferences.refreshIntervalSeconds, 600)
        XCTAssertEqual(PreferencesStore.normalizedRefreshInterval(123), 60)

        let reloaded = PreferencesStore(defaults: suite)
        XCTAssertEqual(reloaded.refreshIntervalSeconds, 600)
    }
}
