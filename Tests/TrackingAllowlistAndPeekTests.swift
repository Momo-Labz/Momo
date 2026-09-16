import Foundation
import XCTest
@testable import BAR_BOY

@MainActor
final class TrackingAllowlistAndPeekTests: XCTestCase {
    func testAllowedTrackingProvidersPersistLocally() {
        let suite = UserDefaults(suiteName: "MomoTrackingAllow.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertFalse(preferences.trackingOnboardingSeen)
        XCTAssertTrue(preferences.allowedTrackingProviders.isEmpty)
        XCTAssertEqual(preferences.trackingStripProviders(), [])

        preferences.setAllowedTrackingProviders([.claude, .cursor])
        XCTAssertTrue(preferences.trackingOnboardingSeen)
        XCTAssertEqual(preferences.allowedTrackingProviders, [.claude, .cursor])
        XCTAssertEqual(preferences.trackingStripProviders(), [.claude, .cursor])

        let reloaded = PreferencesStore(defaults: suite)
        XCTAssertTrue(reloaded.trackingOnboardingSeen)
        XCTAssertEqual(reloaded.allowedTrackingProviders, [.claude, .cursor])
        XCTAssertTrue(reloaded.isTrackingAllowed(.claude))
        XCTAssertFalse(reloaded.isTrackingAllowed(.codex))
    }

    func testOnboardingIntentsPersistAndGateTips() {
        let suite = UserDefaults(suiteName: "MomoOnboardingIntents.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let preferences = PreferencesStore(defaults: suite)
        XCTAssertTrue(preferences.onboardingIntents.isEmpty)
        XCTAssertFalse(preferences.prefersUsageTips())
        XCTAssertFalse(preferences.prefersBrainTips())

        preferences.setOnboardingIntents([.usageTracking, .projectFolders])
        XCTAssertTrue(preferences.prefersUsageTips())
        XCTAssertTrue(preferences.prefersBrainTips())
        XCTAssertEqual(OnboardingIntent.usageTracking.title, "Track usage across models")
        XCTAssertEqual(OnboardingIntent.organizingPrompts.title, "Organize prompts")
        XCTAssertEqual(OnboardingIntent.projectFolders.title, "Keep project folders tidy")

        let reloaded = PreferencesStore(defaults: suite)
        XCTAssertEqual(reloaded.onboardingIntents, [.usageTracking, .projectFolders])
    }

    func testTrackingAllowListIsSeparateFromFolderAuthorization() {
        let suite = UserDefaults(suiteName: "MomoTrackingAllowSeparate.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }

        let preferences = PreferencesStore(defaults: suite)
        preferences.setAllowedTrackingProviders([.gemini, .grok])
        XCTAssertTrue(preferences.enabledProviders.isEmpty)
        preferences.setEnabled(true, for: .codex)
        XCTAssertEqual(preferences.enabledProviders, [.codex])
        XCTAssertEqual(preferences.allowedTrackingProviders, [.gemini, .grok])
    }

    func testProviderStripLayoutFillsProportionally() {
        XCTAssertEqual(
            ProviderStripLayout.visibleProviders(allowed: [.codex, .claude], onboardingSeen: true),
            [.codex, .claude]
        )
        XCTAssertEqual(ProviderStripLayout.visibleProviders(allowed: [.codex], onboardingSeen: false), [])
        XCTAssertNil(ProviderStripLayout.equalCardWidth(availableWidth: 400, count: 0))

        let two = try XCTUnwrap(ProviderStripLayout.equalCardWidth(availableWidth: 400, count: 2, spacing: 7))
        let three = try XCTUnwrap(ProviderStripLayout.equalCardWidth(availableWidth: 400, count: 3, spacing: 7))
        XCTAssertEqual(two, (400 - 7) / 2, accuracy: 0.001)
        XCTAssertEqual(three, (400 - 14) / 3, accuracy: 0.001)
        XCTAssertGreaterThan(two, three)
    }

    func testProviderConnectOpensAccountLoginWithoutUsageCaptureURL() {
        let original = ProviderAccountOpen.openURL
        defer { ProviderAccountOpen.openURL = original }

        var opened: [URL] = []
        ProviderAccountOpen.openURL = { url in
            opened.append(url)
            return true
        }

        XCTAssertTrue(ProviderAccountOpen.openLogin(for: .codex))
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first, AIProvider.codex.accountLoginURL)
        XCTAssertNotEqual(opened.first, AIProvider.codex.usageURL)
        XCTAssertEqual(AIProvider.codex.connectButtonTitle, "Continue with Codex / ChatGPT")
    }

    func testUsageReturnOfferDoesNotAutoOpenCaptureRoute() {
        let surface = MomoSurface.shared
        surface.dismissUsageReturn()
        let routeBefore = surface.route
        surface.offerUsageReturn([.claude, .cursor])
        XCTAssertEqual(surface.pendingUsageReturn, [.claude, .cursor])
        XCTAssertEqual(surface.route, routeBefore)
        surface.dismissUsageReturn()
        XCTAssertTrue(surface.pendingUsageReturn.isEmpty)
    }

    func testPeekMappingUsesFiveHourAndWeeklyWhenPresent() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let observations = [
            ProviderUsageObservation(
                provider: .codex,
                metric: "5-hour limit",
                percentage: 12,
                resetsAt: capturedAt.addingTimeInterval(3_600),
                capturedAt: capturedAt,
                freshness: 60 * 60,
                provenance: .localOllama
            ),
            ProviderUsageObservation(
                provider: .codex,
                metric: "Weekly · all models",
                percentage: 100,
                resetsAt: capturedAt.addingTimeInterval(86_400 * 3),
                capturedAt: capturedAt,
                freshness: 60 * 60,
                provenance: .localOllama
            )
        ]
        let mapped = UsagePeekMapping.map(observations: observations, snapshot: nil, now: capturedAt)
        XCTAssertEqual(mapped.fiveHour.percentage, 12)
        XCTAssertEqual(mapped.weekly.percentage, 100)
        XCTAssertEqual(mapped.fiveHour.valueLabel(now: capturedAt), "12% · resets 1h")
        XCTAssertEqual(mapped.weekly.valueLabel(now: capturedAt), "100% · resets 3d")
    }

    func testPeekMappingStaysDashedWhenObservationsAbsentOrUnmapped() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = UsagePeekMapping.map(observations: [], snapshot: nil, now: capturedAt)
        XCTAssertNil(empty.fiveHour.percentage)
        XCTAssertNil(empty.weekly.percentage)
        XCTAssertEqual(empty.fiveHour.valueLabel(now: capturedAt), "—")
        XCTAssertEqual(empty.weekly.valueLabel(now: capturedAt), "—")

        let unrelated = [
            ProviderUsageObservation(
                provider: .claude,
                metric: "Tokens today",
                percentage: 40,
                resetsAt: nil,
                capturedAt: capturedAt,
                freshness: 60 * 60,
                provenance: .officialWeb
            )
        ]
        let mapped = UsagePeekMapping.map(observations: unrelated, snapshot: nil, now: capturedAt)
        XCTAssertNil(mapped.fiveHour.percentage)
        XCTAssertNil(mapped.weekly.percentage)
    }

    func testPeekRowsIncludeOnlyAllowedProviders() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let observations = [
            ProviderUsageObservation(
                provider: .cursor,
                metric: "5HR",
                percentage: 33,
                resetsAt: nil,
                capturedAt: capturedAt,
                freshness: 60 * 60,
                provenance: .providerEvent
            )
        ]
        let rows = UsagePeekMapping.rows(
            allowed: [.claude, .cursor],
            observations: observations,
            snapshots: [],
            now: capturedAt
        )
        XCTAssertEqual(rows.map(\.provider), [.claude, .cursor])
        XCTAssertNil(rows[0].fiveHour.percentage)
        XCTAssertEqual(rows[1].fiveHour.percentage, 33)
        XCTAssertNil(rows[1].weekly.percentage)
    }

    func testMetricClassifierRecognizesCommonLabels() {
        XCTAssertTrue(UsagePeekMapping.matches("5HR", kind: .fiveHour))
        XCTAssertTrue(UsagePeekMapping.matches("5-hour limit", kind: .fiveHour))
        XCTAssertTrue(UsagePeekMapping.matches("Weekly", kind: .weekly))
        XCTAssertTrue(UsagePeekMapping.matches("1 week", kind: .weekly))
        XCTAssertFalse(UsagePeekMapping.matches("Weekly", kind: .fiveHour))
        XCTAssertFalse(UsagePeekMapping.matches("5-hour limit", kind: .weekly))
    }
}
