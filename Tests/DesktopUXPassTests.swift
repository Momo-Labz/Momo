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
        XCTAssertEqual(
            DesktopConnectionVerifier.evaluate(
                provider: .claude,
                isInstalled: true,
                isRunning: true,
                hasReadableSessionSource: false,
                privacyBlocked: true
            ),
            .privacyBlocked
        )
        XCTAssertTrue(
            DesktopConnectionVerifier.Status.privacyBlocked.guidance.contains("Full Disk Access")
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

    func testOnboardingSchemaIsV6ForForcedConnect() {
        XCTAssertEqual(PreferencesStore.currentOnboardingSchemaVersion, 6)
        let suite = UserDefaults(suiteName: "MomoSchemaV6UX.\(UUID().uuidString)")!
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

    func testConnectUsageHonestyReportsFoundMissingAndBlocked() {
        let found = ConnectUsageHonesty(
            outcome: .usageFound(sessionPercent: 27, weekPercent: 100),
            sourcePath: "/tmp/claude/statusline-usage-cache.json"
        )
        XCTAssertTrue(found.summary.contains("27%"))
        XCTAssertTrue(found.summary.contains("100%"))
        XCTAssertFalse(found.summary.contains("invent"))

        let missing = ConnectUsageHonesty(outcome: .noReadableCache, sourcePath: nil)
        XCTAssertTrue(missing.summary.contains("no readable usage cache"))

        let blocked = ConnectUsageHonesty(outcome: .privacyBlocked, sourcePath: nil)
        XCTAssertTrue(blocked.summary.contains("Full Disk Access"))

        XCTAssertEqual(
            DesktopConnectionVerifier.progress(
                from: .verified,
                honesty: found
            ),
            .connected(found)
        )
        XCTAssertEqual(
            DesktopConnectionVerifier.progress(from: .privacyBlocked, honesty: blocked),
            .needsPermission
        )
        XCTAssertTrue(DesktopConnectProgress.openingApp.showsSpinner)
        XCTAssertFalse(DesktopConnectProgress.timedOut.showsSpinner)
    }

    func testUsageHonestyFromVerifiedStatusWithoutInventing() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("momo-honesty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let withoutCache = DesktopConnectionVerifier.usageHonesty(
            for: .claude,
            status: .verified,
            home: tmp
        )
        XCTAssertEqual(withoutCache?.outcome, .noReadableCache)

        let cacheDir = tmp.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "five_hour": ["utilization": 12.0],
            "seven_day": ["utilization": 34.0]
        ]
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: cacheDir.appendingPathComponent("usage-cache.json"))

        let withCache = DesktopConnectionVerifier.usageHonesty(
            for: .claude,
            status: .verified,
            home: tmp
        )
        guard case .usageFound(let session, let week) = withCache?.outcome else {
            return XCTFail("Expected usageFound")
        }
        XCTAssertEqual(session, 12)
        XCTAssertEqual(week, 34)

        let privacy = DesktopConnectionVerifier.usageHonesty(
            for: .claude,
            status: .privacyBlocked,
            home: tmp
        )
        XCTAssertEqual(privacy?.outcome, .privacyBlocked)
    }

    func testTrackerTabsAreActivityUsageBrainUpgrade() {
        XCTAssertEqual(TrackerTab.allCases.map(\.title), ["Activity", "Usage", "Brain", "Upgrade"])
    }

    func testClaudeFlexibleUsageCacheParsesFiveHourAndWeek() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("momo-claude-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cacheDir = tmp.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "five_hour": ["utilization": 27.0, "resets_at": "2026-09-20T20:00:00Z"],
            "seven_day": ["utilization": 100.0, "resets_at": "2026-09-19T18:59:00Z"],
            "cost": [
                "total_cost_usd": 0.0123,
                "total_api_duration_ms": 1500,
                "total_duration_ms": 8000,
                "total_lines_added": 10,
                "total_lines_removed": 2
            ],
            "context_window": [
                "total_input_tokens": 100,
                "total_output_tokens": 40,
                "cache_read_input_tokens": 20,
                "cache_creation_input_tokens": 5
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: cacheDir.appendingPathComponent("usage-cache.json"))

        let detail = LocalUsageArtifactReader.detail(for: .claude, home: tmp, now: .now)
        XCTAssertEqual(Int(detail.fiveHour?.percent ?? -1), 27)
        XCTAssertEqual(Int(detail.weekly?.percent ?? -1), 100)
        XCTAssertNotNil(detail.weekly?.resetsAt)
        XCTAssertEqual(detail.totalCostUSD, 0.0123, accuracy: 0.0001)
        XCTAssertEqual(detail.durationAPISeconds, 1.5, accuracy: 0.01)
        XCTAssertEqual(detail.durationWallSeconds, 8, accuracy: 0.01)
        XCTAssertEqual(detail.linesAdded, 10)
        XCTAssertEqual(detail.linesRemoved, 2)
        XCTAssertEqual(detail.inputTokens, 100)
        XCTAssertEqual(detail.outputTokens, 40)
        XCTAssertEqual(detail.cacheReadTokens, 20)
        XCTAssertEqual(detail.cacheWriteTokens, 5)
        XCTAssertNotNil(LocalUsageArtifactReader.resetCaption(detail.weekly?.resetsAt))

        let statusline: [String: Any] = [
            "rate_limits": [
                "five_hour": ["used_percentage": 18.5, "resets_at": 1_800_000_000],
                "seven_day": ["used_percentage": 42.0, "resets_at": 1_800_086_400]
            ]
        ]
        let parsed = RecordedQuotaWindow.parseFlexible(statusline, observedAt: .now)
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?.first { $0.minutes == 300 }?.percent, 18.5)
    }

    func testFlexibleParseNeverInventsFromUnrelatedJSON() {
        XCTAssertNil(RecordedQuotaWindow.parseFlexible(["hello": "world"], observedAt: .now))
        let invalid = RecordedQuotaWindow.parseFlexible(
            ["five_hour": ["used_percentage": 250], "seven_day": ["used_percentage": -1]],
            observedAt: .now
        )
        XCTAssertNotNil(invalid)
        XCTAssertTrue(invalid?.isEmpty == true)
        XCTAssertTrue(LocalUsageDetail.parse(["hello": "world"], observedAt: .now).isEmpty)
    }
}
