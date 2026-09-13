import Combine
import Foundation

/// Local-only bridge for MOMO Brain and agent assistance.
/// It never sends prompts to a remote host and stays idle until the Brain page checks it.
@MainActor
final class OllamaService: ObservableObject {
    @Published private(set) var statusText = "CHECKING LOCAL OLLAMA"
    @Published private(set) var models: [String] = []

    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    var isAvailable: Bool { !models.isEmpty }
    var preferredModel: String? { models.first }

    func refresh() async {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                models = []
                statusText = "OLLAMA UNAVAILABLE"
                return
            }
            let payload = try JSONDecoder().decode(TagResponse.self, from: data)
            models = payload.models.map(\.name).filter { !$0.isEmpty }
            statusText = models.isEmpty ? "NO LOCAL MODEL" : "OLLAMA · \(models.count) MODEL\(models.count == 1 ? "" : "S")"
        } catch {
            models = []
            statusText = "OLLAMA OFFLINE"
        }
    }

    func complete(prompt: String, model: String? = nil) async -> String? {
        guard let chosen = model ?? preferredModel else { return nil }
        let boundedPrompt = String(prompt.prefix(12_000))
        let body = GenerateRequest(model: chosen, prompt: boundedPrompt, stream: false)
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try? JSONDecoder().decode(GenerateResponse.self, from: responseData) else { return nil }
        return result.response
    }

    private struct TagResponse: Decodable {
        let models: [Model]
        struct Model: Decodable { let name: String }
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable { let response: String }
}
