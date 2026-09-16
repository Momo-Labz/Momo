import CryptoKit
import Foundation
import WebKit

enum UsageCaptureState: String, Equatable {
    case idle
    case loading
    case ready
    case parsing
    case offline
    case malformed
    case cancelled
    case failed
}

@MainActor
final class UsageCaptureService: NSObject, ObservableObject, WKNavigationDelegate {
    static let visibleTextByteLimit = 64 * 1024
    static let interpretationCacheLifetime: TimeInterval = 5 * 60

    @Published private(set) var activeProvider: AIProvider?
    @Published private(set) var state: UsageCaptureState = .idle
    @Published private(set) var status = "IDLE"

    private struct InterpretationCacheEntry {
        let observations: [ProviderUsageObservation]
        let expiresAt: Date
    }

    private let ollama: OllamaService
    private let cache: TrackingCache
    private let now: () -> Date
    private var webViewProvider: [ObjectIdentifier: AIProvider] = [:]
    private var interpretationCache: [String: InterpretationCacheEntry] = [:]
    private var interpretationID: UUID?

    init(
        ollama: OllamaService? = nil,
        cache: TrackingCache = TrackingCache(),
        now: @escaping () -> Date = { .now }
    ) {
        self.ollama = ollama ?? OllamaService.shared
        self.cache = cache
        self.now = now
        super.init()
    }

    /// Creates a cookie-isolated view for one official provider page.
    /// MOMO never imports browser cookies, user scripts, local storage, or provider credentials.
    func makeWebView(for provider: AIProvider) -> WKWebView? {
        guard let url = provider.usageURL, Self.isAllowedCapture(url, for: provider) else {
            activeProvider = provider
            state = .failed
            status = "USAGE PAGE UNAVAILABLE"
            return nil
        }
        let configuration = WKWebViewConfiguration()
        // WKWebView's default store persists only MOMO's own WebKit session. It does
        // not import Safari, Chrome, or another app's cookies or local storage.
        configuration.websiteDataStore = .default()
        configuration.userContentController = WKUserContentController()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webViewProvider[ObjectIdentifier(view)] = provider
        activeProvider = provider
        state = .loading
        status = "OPENING \(provider.name.uppercased())"
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return view
    }

    func observations(from webView: WKWebView) async -> [ProviderUsageObservation] {
        guard let provider = webViewProvider[ObjectIdentifier(webView)],
              let url = webView.url, Self.isAllowedCapture(url, for: provider) else {
            state = .failed
            status = "CAPTURE BLOCKED"
            return []
        }
        guard let visibleText = await visibleText(from: webView), !visibleText.isEmpty else {
            state = .malformed
            status = "NO VISIBLE USAGE"
            return []
        }
        return await observations(provider: provider, visibleText: visibleText)
    }

    func observations(provider: AIProvider, visibleText: String) async -> [ProviderUsageObservation] {
        let text = Self.boundedVisibleText(visibleText)
        guard !text.isEmpty else { return [] }
        let capturedAt = now()
        let digest = SHA256.hash(data: Data("\(provider.rawValue)\n\(text)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        interpretationCache = interpretationCache.filter { $0.value.expiresAt >= capturedAt }
        if let entry = interpretationCache[digest], entry.expiresAt >= capturedAt {
            state = .ready
            status = entry.observations.isEmpty ? "USAGE UNKNOWN" : "USAGE READY · CACHED"
            return entry.observations
        }

        let prompt = Self.interpretationPrompt(provider: provider, visibleText: text)
        let requestID = UUID()
        interpretationID = requestID
        state = .parsing
        status = "PARSING LOCALLY"
        guard let response = await ollama.complete(prompt: prompt, sourceRevision: digest) else {
            guard interpretationID == requestID else { return [] }
            interpretationID = nil
            switch ollama.state {
            case .offline, .timedOut:
                state = .offline
                status = "LOCAL PARSER OFFLINE"
            case .cancelled:
                state = .cancelled
                status = "CAPTURE CANCELLED"
            default:
                state = .failed
                status = "LOCAL PARSER UNAVAILABLE"
            }
            return []
        }
        guard interpretationID == requestID else { return [] }
        interpretationID = nil
        guard let observations = UsageObservationJSON.parse(
            response,
            provider: provider,
            capturedAt: capturedAt,
            freshness: TrackingCache.acceptedObservationFreshness
        ) else {
            state = .malformed
            status = "USAGE RESPONSE REJECTED"
            return []
        }
        interpretationCache[digest] = InterpretationCacheEntry(
            observations: observations,
            expiresAt: capturedAt.addingTimeInterval(Self.interpretationCacheLifetime)
        )
        state = .ready
        status = observations.isEmpty ? "USAGE UNKNOWN" : "USAGE READY"
        return observations
    }

    /// Persists a previously previewed observation set. Preview never writes.
    @discardableResult
    func acceptPreview(_ observations: [ProviderUsageObservation]) async -> Int {
        let count = await cache.accept(observations, now: now())
        state = .ready
        if count > 0 {
            status = "USAGE SAVED"
        } else if observations.isEmpty {
            status = "NOTHING TO SAVE"
        } else {
            status = "SAVE REJECTED"
        }
        return count
    }

    func acceptedObservations(for provider: AIProvider? = nil) async -> [ProviderUsageObservation] {
        await cache.observations(for: provider, now: now())
    }

    func cancel() {
        guard interpretationID != nil else { return }
        interpretationID = nil
        ollama.cancel()
        state = .cancelled
        status = "CAPTURE CANCELLED"
    }

    /// Short operator-facing copy for the connect panel. Does not invent usage values.
    var guidance: String {
        switch state {
        case .idle:
            return "Open the official usage page, sign in if needed, then preview. Nothing is saved until you confirm."
        case .loading:
            return "Opening \(activeProvider?.name ?? "provider")'s official usage page in an isolated WebKit view."
        case .ready:
            return status == "USAGE SAVED"
                ? "Saved to the local usage cache. You can go back to Tracking."
                : status == "USAGE READY" || status == "USAGE READY · CACHED"
                ? "Preview ready. Confirm only if the values match what you see on the page."
                : status == "USAGE UNKNOWN"
                ? "The page loaded, but no explicit usage values were present in the visible text."
                : "Sign in inside this page if needed. Stay on the official usage page, then preview."
        case .parsing:
            return "Local Ollama is reading only the visible text on this page."
        case .offline:
            return "The usage page or local parser is offline. MOMO will not invent a value."
        case .malformed:
            return "No explicit usage values were found in the visible text."
        case .cancelled:
            return "Capture was cancelled."
        case .failed:
            return status == "USAGE PAGE UNAVAILABLE"
                ? "No allowlisted official usage page is available for this provider yet."
                : "Capture could not continue on this page."
        }
    }

    static func isAllowedCapture(_ url: URL, for provider: AIProvider) -> Bool {
        isSecure(url) && providerPageHosts[provider, default: []].contains(url.host?.lowercased() ?? "")
    }

    static func isAllowedNavigation(_ url: URL, for provider: AIProvider) -> Bool {
        guard isSecure(url) else { return false }
        let host = url.host?.lowercased() ?? ""
        return providerPageHosts[provider, default: []].contains(host)
            || authenticationHosts[provider, default: []].contains(host)
    }

    private static func isSecure(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              url.host != nil else { return false }
        return true
    }

    static func boundedVisibleText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Data(normalized.utf8)
        guard bytes.count > visibleTextByteLimit else { return normalized }
        var end = visibleTextByteLimit
        while end > 0 {
            if let value = String(data: bytes.prefix(end), encoding: .utf8) { return value }
            end -= 1
        }
        return ""
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let provider = webViewProvider[ObjectIdentifier(webView)],
              let url = navigationAction.request.url,
              Self.isAllowedNavigation(url, for: provider) else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .ready
        status = "READY TO CAPTURE"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state = (error as? URLError)?.code == .cancelled ? .cancelled : .offline
        status = state == .cancelled ? "CAPTURE CANCELLED" : "USAGE PAGE OFFLINE"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    private func visibleText(from webView: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { value, _ in
                continuation.resume(returning: (value as? String).map(Self.boundedVisibleText))
            }
        }
    }

    private static let providerPageHosts: [AIProvider: Set<String>] = [
        .codex: ["chatgpt.com"],
        .claude: ["claude.ai"],
        .gemini: ["aistudio.google.com"],
        .cursor: ["cursor.com"],
        .grok: ["grok.com"]
    ]

    private static let authenticationHosts: [AIProvider: Set<String>] = [
        .codex: ["auth.openai.com"],
        .claude: [],
        .gemini: ["accounts.google.com"],
        .cursor: ["authenticator.cursor.sh"],
        // xAI documents sign-in management at accounts.x.ai; X SSO still uses x.com.
        .grok: ["x.com", "accounts.x.ai"]
    ]

    private static func interpretationPrompt(provider: AIProvider, visibleText: String) -> String {
        """
        Extract only usage values explicitly present in the visible text from \(provider.name)'s official usage page.
        Return exactly one JSON object: {"observations":[{"metric":"name","percentage":75,"resetsAt":"2026-09-14T12:00:00Z"}]}.
        percentage must be an integer from 0 through 100 or null. resetsAt must be ISO-8601 or null.
        Use an empty observations array when the text does not state a value. Do not estimate or infer missing values.

        VISIBLE TEXT:
        \(visibleText)
        """
    }
}

extension AIProvider {
    /// True when MOMO has an official HTTPS usage URL on an allowlisted host.
    var supportsUsageCapture: Bool {
        guard let url = usageURL else { return false }
        return UsageCaptureService.isAllowedCapture(url, for: self)
    }
}

enum UsageObservationJSON {
    static func parse(
        _ text: String,
        provider: AIProvider,
        capturedAt: Date,
        freshness: TimeInterval
    ) -> [ProviderUsageObservation]? {
        guard let data = text.data(using: .utf8), data.count <= 64 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["observations"]),
              let records = root["observations"] as? [[String: Any]], records.count <= 8 else { return nil }

        let formatter = ISO8601DateFormatter()
        var observations: [ProviderUsageObservation] = []
        for record in records {
            guard Set(record.keys) == Set(["metric", "percentage", "resetsAt"]),
                  let rawMetric = record["metric"] as? String else { return nil }
            let metric = rawMetric.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metric.isEmpty, metric.count <= 80, !metric.contains("\n") else { return nil }

            let percentage: Int?
            if record["percentage"] is NSNull {
                percentage = nil
            } else if let number = record["percentage"] as? NSNumber,
                      String(cString: number.objCType) != "c",
                      number.doubleValue.isFinite,
                      number.doubleValue.rounded(.down) == number.doubleValue,
                      (0...100).contains(number.intValue) {
                percentage = number.intValue
            } else {
                return nil
            }

            let resetsAt: Date?
            if record["resetsAt"] is NSNull {
                resetsAt = nil
            } else if let rawReset = record["resetsAt"] as? String,
                      let parsed = formatter.date(from: rawReset) {
                resetsAt = parsed
            } else {
                return nil
            }

            observations.append(ProviderUsageObservation(
                provider: provider,
                metric: metric,
                percentage: percentage,
                resetsAt: resetsAt,
                capturedAt: capturedAt,
                freshness: freshness,
                provenance: .localOllama
            ))
        }
        return observations
    }
}
