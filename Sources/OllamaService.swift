import Combine
import Foundation

protocol OllamaHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionOllamaClient: OllamaHTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

enum OllamaState: String, Equatable, Sendable {
    case checking
    case offline
    case missingModel
    case ready
    case loading
    case timedOut
    case cancelled
    case failed
    case completed
}

/// Local-only bridge for MOMO Brain and agent assistance.
/// Prompts are accepted only by a loopback Ollama endpoint and generation stays idle until requested.
@MainActor
final class OllamaService: ObservableObject {
    static let shared = OllamaService(persistSelection: true)

    @Published private(set) var statusText = "CHECKING LOCAL OLLAMA"
    @Published private(set) var state: OllamaState = .checking
    @Published private(set) var models: [String] = []
    @Published var selectedModel: String? {
        didSet {
            guard persistSelection else { return }
            defaults.set(selectedModel, forKey: Self.selectedModelKey)
        }
    }
    @Published private(set) var isGenerating = false

    var isAvailable: Bool { !models.isEmpty }
    var preferredModel: String? { selectedModel ?? models.first }

    private struct CacheEntry {
        let text: String
        let createdAt: Date
        var lastAccessedAt: Date
    }

    private enum GenerationOutcome {
        case success(String)
        case timedOut
        case cancelled
        case failed
    }

    private let baseURL: URL
    private let client: any OllamaHTTPClient
    private let now: @Sendable () -> Date
    private let cacheLifetime: TimeInterval
    private let cacheLimit: Int
    private let refreshInterval: TimeInterval
    private let defaults: UserDefaults
    private let persistSelection: Bool
    private static let selectedModelKey = "momo.ollama.selectedModel"
    private var cache: [String: CacheEntry] = [:]
    private var checking = false
    private var lastCheck: Date?
    private var generationTask: Task<GenerationOutcome, Never>?
    private var generationID: UUID?

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        client: any OllamaHTTPClient = URLSessionOllamaClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        cacheLifetime: TimeInterval = 300,
        cacheLimit: Int = 12,
        refreshInterval: TimeInterval = 120,
        defaults: UserDefaults = .standard,
        persistSelection: Bool = false
    ) {
        precondition(baseURL.host == "127.0.0.1" || baseURL.host == "localhost", "Ollama must remain local")
        self.baseURL = baseURL
        self.client = client
        self.now = now
        self.cacheLifetime = cacheLifetime
        self.cacheLimit = max(1, cacheLimit)
        self.refreshInterval = max(0, refreshInterval)
        self.defaults = defaults
        self.persistSelection = persistSelection
        selectedModel = persistSelection ? defaults.string(forKey: Self.selectedModelKey) : nil
    }

    func refresh(force: Bool = false) async {
        let checkDate = now()
        guard !checking else { return }
        guard force || lastCheck.map({ checkDate.timeIntervalSince($0) >= refreshInterval }) ?? true else { return }
        checking = true
        state = .checking
        statusText = "CHECKING LOCAL OLLAMA"
        defer {
            checking = false
            lastCheck = checkDate
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        do {
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                markOffline()
                return
            }
            let payload = try JSONDecoder().decode(TagResponse.self, from: data)
            models = Array(Set(payload.models.map(\.name).filter { !$0.isEmpty })).sorted()
            if let selectedModel, !models.contains(selectedModel) {
                self.selectedModel = nil
            }
            if self.selectedModel == nil {
                self.selectedModel = models.first
            }
            if models.isEmpty {
                state = .missingModel
                statusText = "NO LOCAL MODEL"
            } else {
                state = .ready
                statusText = "OLLAMA · \(models.count) MODEL\(models.count == 1 ? "" : "S")"
            }
        } catch {
            markOffline()
        }
    }

    /// Completes one local generation. A second request is declined while one is active.
    /// The source revision keeps cached answers from surviving a vault change.
    func complete(prompt: String, model: String? = nil, sourceRevision: String = "") async -> String? {
        let chosen = model ?? preferredModel
        guard let chosen, !chosen.isEmpty else {
            state = .missingModel
            statusText = "NO LOCAL MODEL"
            return nil
        }
        guard generationTask == nil else { return nil }

        pruneCache()
        let boundedPrompt = String(prompt.prefix(12_000))
        let key = [chosen, sourceRevision, boundedPrompt].joined(separator: "\n")
        if var entry = cache[key], now().timeIntervalSince(entry.createdAt) < cacheLifetime {
            entry.lastAccessedAt = now()
            cache[key] = entry
            state = .completed
            statusText = "ANSWER READY · CACHED"
            return entry.text
        }

        let body = GenerateRequest(model: chosen, prompt: boundedPrompt, stream: false)
        guard let data = try? JSONEncoder().encode(body) else {
            state = .failed
            statusText = "OLLAMA REQUEST ERROR"
            return nil
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        isGenerating = true
        state = .loading
        statusText = "OLLAMA THINKING"
        selectedModel = chosen
        let requestID = UUID()
        generationID = requestID
        let client = self.client
        let task = Task<GenerationOutcome, Never> {
            do {
                let (responseData, response) = try await client.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return .failed
                }
                let result = try JSONDecoder().decode(GenerateResponse.self, from: responseData)
                let answer = result.response.trimmingCharacters(in: .whitespacesAndNewlines)
                return answer.isEmpty ? .failed : .success(String(answer.prefix(16_000)))
            } catch is CancellationError {
                return .cancelled
            } catch let error as URLError where error.code == .timedOut {
                return .timedOut
            } catch {
                return .failed
            }
        }
        generationTask = task
        let outcome = await task.value

        guard generationID == requestID else { return nil }
        generationTask = nil
        generationID = nil
        isGenerating = false

        switch outcome {
        case .cancelled:
            state = .cancelled
            statusText = "OLLAMA CANCELLED"
            return nil
        case .timedOut:
            state = .timedOut
            statusText = "OLLAMA TIMED OUT"
            return nil
        case .failed:
            state = .failed
            statusText = "OLLAMA RESPONSE ERROR"
            return nil
        case .success(let answer):
            let date = now()
            cache[key] = CacheEntry(text: answer, createdAt: date, lastAccessedAt: date)
            pruneCache()
            state = .completed
            statusText = "ANSWER READY"
            return answer
        }
    }

    func cancel() {
        guard generationTask != nil else { return }
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
        isGenerating = false
        state = .cancelled
        statusText = "OLLAMA CANCELLED"
    }

    func clearAnswerCache() {
        cache.removeAll(keepingCapacity: false)
    }

    private func markOffline() {
        models = []
        selectedModel = nil
        state = .offline
        statusText = "OLLAMA OFFLINE"
    }

    private func pruneCache() {
        let cutoff = now().addingTimeInterval(-cacheLifetime)
        cache = cache.filter { $0.value.createdAt >= cutoff }
        guard cache.count > cacheLimit else { return }
        let oldest = cache.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
        for entry in oldest.prefix(cache.count - cacheLimit) {
            cache.removeValue(forKey: entry.key)
        }
    }

    private struct TagResponse: Decodable {
        let models: [Model]
        struct Model: Decodable { let name: String }
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let keep_alive = "30s"
        let options = Options()

        struct Options: Encodable {
            let num_ctx = 4096
            let num_predict = 384
        }
    }

    private struct GenerateResponse: Decodable { let response: String }
}
