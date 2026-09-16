import Foundation
import XCTest
@testable import BAR_BOY

@MainActor
final class UsageCaptureTests: XCTestCase {
    private actor StubOllamaClient: OllamaHTTPClient {
        let responseJSON: String

        init(responseJSON: String) {
            self.responseJSON = responseJSON
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/api/tags" {
                return (try JSONSerialization.data(withJSONObject: ["models": [["name": "momo-local"]]]), response)
            }
            return (try JSONSerialization.data(withJSONObject: ["response": responseJSON]), response)
        }
    }

    func testOfficialUsageURLsStayOnAllowlistedHosts() throws {
        XCTAssertEqual(AIProvider.claude.usageURL?.absoluteString, "https://claude.ai/settings/usage")
        XCTAssertEqual(AIProvider.cursor.usageURL?.absoluteString, "https://cursor.com/dashboard/usage")
        XCTAssertEqual(AIProvider.grok.usageURL?.absoluteString, "https://grok.com/?_s=usage")
        for provider in AIProvider.allCases {
            XCTAssertTrue(provider.supportsUsageCapture, "\(provider.name) should expose a connectable usage path")
            let url = try XCTUnwrap(provider.usageURL)
            XCTAssertTrue(UsageCaptureService.isAllowedCapture(url, for: provider))
        }
    }

    func testNavigationAllowlistKeepsAuthHostsSeparateFromCaptureHosts() {
        XCTAssertTrue(
            UsageCaptureService.isAllowedNavigation(
                URL(string: "https://authenticator.cursor.sh/login")!,
                for: .cursor
            )
        )
        XCTAssertFalse(
            UsageCaptureService.isAllowedCapture(
                URL(string: "https://authenticator.cursor.sh/login")!,
                for: .cursor
            )
        )
        XCTAssertTrue(
            UsageCaptureService.isAllowedNavigation(URL(string: "https://accounts.x.ai/")!, for: .grok)
        )
        XCTAssertTrue(
            UsageCaptureService.isAllowedNavigation(URL(string: "https://x.com/i/flow/login")!, for: .grok)
        )
        XCTAssertFalse(
            UsageCaptureService.isAllowedCapture(URL(string: "https://accounts.x.ai/")!, for: .grok)
        )
        XCTAssertFalse(
            UsageCaptureService.isAllowedNavigation(URL(string: "http://claude.ai/settings/usage")!, for: .claude)
        )
    }

    func testUsageObservationJSONRejectsInventedShapes() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = UsageObservationJSON.parse(
            #"{"observations":[{"metric":"Weekly","percentage":42,"resetsAt":null}]}"#,
            provider: .claude,
            capturedAt: capturedAt,
            freshness: TrackingCache.acceptedObservationFreshness
        )
        XCTAssertEqual(valid?.count, 1)
        XCTAssertEqual(valid?.first?.metric, "Weekly")
        XCTAssertEqual(valid?.first?.percentage, 42)
        XCTAssertEqual(valid?.first?.provenance, .localOllama)

        XCTAssertNil(
            UsageObservationJSON.parse(
                #"{"observations":[{"metric":"Weekly","percentage":101,"resetsAt":null}]}"#,
                provider: .cursor,
                capturedAt: capturedAt,
                freshness: 60
            )
        )
        XCTAssertNil(
            UsageObservationJSON.parse(
                #"{"usage":75}"#,
                provider: .grok,
                capturedAt: capturedAt,
                freshness: 60
            )
        )
    }

    func testPreviewDoesNotPersistUntilAccept() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("momo-usage-\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let json = #"{"observations":[{"metric":"Pool","percentage":18,"resetsAt":null}]}"#
        let ollama = OllamaService(client: StubOllamaClient(responseJSON: json), refreshInterval: 0)
        await ollama.refresh(force: true)
        XCTAssertEqual(ollama.state, .ready)

        let cache = TrackingCache(databaseURL: databaseURL)
        let service = UsageCaptureService(ollama: ollama, cache: cache)
        let preview = await service.observations(
            provider: .cursor,
            visibleText: "Usage Pool 18% remaining this week"
        )
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview.first?.percentage, 18)
        XCTAssertEqual(service.state, .ready)
        XCTAssertEqual(await cache.observations(for: .cursor), [])

        let saved = await service.acceptPreview(preview)
        XCTAssertEqual(saved, 1)
        let accepted = await cache.observations(for: .cursor)
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(accepted.first?.metric, "Pool")
        XCTAssertEqual(accepted.first?.provenance, .localOllama)
    }

    func testOfflineParserSurfacesTruthfulState() async {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("momo-usage-offline-\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let ollama = OllamaService(
            client: StubOllamaClient(responseJSON: #"{"observations":[]}"#),
            refreshInterval: 0
        )
        // Never refresh — no models, so complete() fails with missing model / unavailable.
        let service = UsageCaptureService(ollama: ollama, cache: TrackingCache(databaseURL: databaseURL))
        let preview = await service.observations(provider: .claude, visibleText: "Weekly usage 40%")
        XCTAssertTrue(preview.isEmpty)
        XCTAssertTrue([UsageCaptureState.failed, .offline].contains(service.state))
        XCTAssertFalse(service.guidance.isEmpty)
    }

    func testBoundedVisibleTextCapsPayload() {
        let oversized = String(repeating: "a", count: UsageCaptureService.visibleTextByteLimit + 2_048)
        let bounded = UsageCaptureService.boundedVisibleText(oversized)
        XCTAssertLessThanOrEqual(bounded.utf8.count, UsageCaptureService.visibleTextByteLimit)
        XCTAssertFalse(bounded.contains("\0"))
    }
}
