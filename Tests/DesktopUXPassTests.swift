import XCTest
@testable import BAR_BOY

@MainActor
final class DesktopUXPassTests: XCTestCase {
    func testTopChatsPerProviderCapsAtThree() {
        let now = Date()
        var sessions: [AgentSession] = []
        for i in 0..<5 {
            sessions.append(
                AgentSession(
                    id: "codex-\(i)",
                    provider: .codex,
                    role: .main,
                    title: "Codex chat \(i)",
                    detail: "",
                    project: "P",
                    updatedAt: now.addingTimeInterval(TimeInterval(-i)),
                    isRunning: i == 0,
                    processID: nil,
                    tokens: nil
                )
            )
        }
        for i in 0..<4 {
            sessions.append(
                AgentSession(
                    id: "claude-\(i)",
                    provider: .claude,
                    role: .main,
                    title: "Claude chat \(i)",
                    detail: "",
                    project: "P",
                    updatedAt: now.addingTimeInterval(TimeInterval(-i)),
                    isRunning: false,
                    processID: nil,
                    tokens: nil
                )
            )
        }

        let limited = SessionPresentation.topChatsPerProvider(sessions, limit: 3)
        XCTAssertEqual(limited.filter { $0.provider == .codex }.count, 3)
        XCTAssertEqual(limited.filter { $0.provider == .claude }.count, 3)
        XCTAssertEqual(limited.filter { $0.provider == .codex }.first?.title, "Codex chat 0")
    }

    func testConnectionVerifierRequiresReadableSourceNotJustRunning() {
        XCTAssertEqual(
            DesktopConnectionVerifier.evaluate(
                provider: .claude,
                isInstalled: true,
                isRunning: true,
                hasReadableSessionSource: false
            ),
            .awaitingSignIn
        )
        XCTAssertEqual(
            DesktopConnectionVerifier.evaluate(
                provider: .claude,
                isInstalled: true,
                isRunning: false,
                hasReadableSessionSource: true
            ),
            .notRunning
        )
        XCTAssertEqual(
            DesktopConnectionVerifier.evaluate(
                provider: .claude,
                isInstalled: false,
                isRunning: false,
                hasReadableSessionSource: false
            ),
            .notInstalled
        )
        XCTAssertTrue(
            DesktopConnectionVerifier.evaluate(
                provider: .claude,
                isInstalled: true,
                isRunning: true,
                hasReadableSessionSource: true
            ).isVerified
        )
        XCTAssertTrue(
            DesktopConnectionVerifier.Status.awaitingSignIn.guidance.contains("Finish signing in")
        )
    }

    func testUsagePeekAlwaysMapsBothWindowsWithoutInventing() {
        let empty = UsagePeekMapping.map(observations: [], snapshot: nil)
        XCTAssertNil(empty.fiveHour.percentage)
        XCTAssertNil(empty.weekly.percentage)
        XCTAssertEqual(empty.fiveHour.valueLabel(), "—")
        XCTAssertEqual(empty.weekly.valueLabel(), "—")

        var snapshot = ProviderSnapshot(
            provider: .codex,
            sessions: [],
            activeCount: 0,
            localTokensToday: 0,
            updatedAt: .now,
            shortWindowPercent: 12,
            weekWindowPercent: 44,
            isInstalled: true
        )
        snapshot.recordedQuotas = [
            RecordedQuotaWindow(percent: 12, minutes: 300, resetsAt: .now.addingTimeInterval(3_600), observedAt: .now),
            RecordedQuotaWindow(percent: 44, minutes: 10_080, resetsAt: .now.addingTimeInterval(86_400), observedAt: .now)
        ]
        let mapped = UsagePeekMapping.map(observations: [], snapshot: snapshot)
        XCTAssertEqual(mapped.fiveHour.percentage, 12)
        XCTAssertEqual(mapped.weekly.percentage, 44)
    }

    func testOnboardingSchemaIsV4ForVerifiedConnect() {
        XCTAssertEqual(PreferencesStore.currentOnboardingSchemaVersion, 4)
        let suite = UserDefaults(suiteName: "MomoSchemaV4.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.suiteName!) }
        suite.set(true, forKey: "trackingOnboardingSeen.v1")
        suite.set(3, forKey: "trackingOnboardingSchemaVersion.v1")
        suite.set(true, forKey: "trackingOnboardingComplete.v3")
        suite.set([AIProvider.codex.rawValue], forKey: "allowedTrackingProviders.v1")
        let preferences = PreferencesStore(defaults: suite)
        XCTAssertTrue(preferences.needsTrackingOnboarding)
        XCTAssertTrue(preferences.allowedTrackingProviders.isEmpty)
    }
}
