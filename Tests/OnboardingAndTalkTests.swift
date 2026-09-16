import Foundation
import XCTest
@testable import BAR_BOY

@MainActor
final class OnboardingAndTalkTests: XCTestCase {
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
        // Allow-list retained for Replay chooser; strip stays empty until Welcome finishes again.
        XCTAssertEqual(preferences.allowedTrackingProviders, [.codex, .claude])
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
        XCTAssertEqual(TalkQuotaStore.UpsellCopy.inline, "You’ve used your free Talk asks. MOMO+ keeps answering about your usage and activity on this Mac — still local, still no invented quotas.")
        XCTAssertEqual(TalkQuotaStore.UpsellCopy.primaryButton, "Continue with MOMO+")
        XCTAssertEqual(TalkQuotaStore.UpsellCopy.secondaryButton, "Not now")
        XCTAssertEqual(
            TalkQuotaStore.UpsellCopy.optionalOneLiner,
            "Plus also unlocks scheduled refresh, all providers, and “tell me before you hit the wall” alerts."
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
}
