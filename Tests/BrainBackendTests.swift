import Darwin
import Foundation
import XCTest
@testable import BAR_BOY

@MainActor
final class BrainBackendTests: XCTestCase {
    private actor MockOllamaClient: OllamaHTTPClient {
        enum GenerateBehavior: Sendable {
            case answer
            case malformed
            case timeout
            case delayed
        }

        private var modelNames: [String]
        private var behavior: GenerateBehavior
        private var generationCount = 0

        init(models: [String] = ["momo-local"], behavior: GenerateBehavior = .answer) {
            modelNames = models
            self.behavior = behavior
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/api/tags" {
                let models = modelNames.map { ["name": $0] }
                return (try JSONSerialization.data(withJSONObject: ["models": models]), response)
            }

            generationCount += 1
            switch behavior {
            case .answer:
                return (try JSONSerialization.data(withJSONObject: ["response": "answer-\(generationCount)"]), response)
            case .malformed:
                return (Data("not-json".utf8), response)
            case .timeout:
                throw URLError(.timedOut)
            case .delayed:
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return (try JSONSerialization.data(withJSONObject: ["response": "late answer"]), response)
            }
        }

        func count() -> Int { generationCount }
        func setModels(_ names: [String]) { modelNames = names }
        func setBehavior(_ newBehavior: GenerateBehavior) { behavior = newBehavior }
    }

    func testVaultResolvesExplicitLinksAndLeavesDuplicateNamesUnresolved() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("# Shared A", to: root.appendingPathComponent("A/Shared.md"))
        try write("# Shared B", to: root.appendingPathComponent("B/Shared.md"))
        try write("# Root\n[[Shared]]\n[[A/Shared]]\n[Other](B/Shared.md) #brain", to: root.appendingPathComponent("Root.md"))

        let index = VaultIndexService()
        let snapshot = try await index.connect(root)
        let note = try XCTUnwrap(snapshot.notes.first { $0.id == "Root.md" })
        XCTAssertEqual(note.links, ["A/Shared.md", "B/Shared.md"])
        XCTAssertEqual(note.unresolvedLinks, ["Shared"])
        XCTAssertEqual(note.tags, ["brain"])
    }

    func testVaultRefreshDropsDeletedNotesAndDoesNotReparseUnchangedNotes() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First.md")
        try write("# First", to: first)
        try write("# Second", to: root.appendingPathComponent("Second.md"))
        let index = VaultIndexService()
        let initial = try await index.connect(root)
        XCTAssertEqual(initial.notes.count, 2)
        let initialMetrics = await index.metrics()
        XCTAssertEqual(initialMetrics.reparsedNoteCount, 2)

        let unchanged = try await index.refresh()
        XCTAssertEqual(unchanged.revision, initial.revision)
        let unchangedMetrics = await index.metrics()
        XCTAssertEqual(unchangedMetrics.reparsedNoteCount, 0)

        try FileManager.default.removeItem(at: first)
        let afterDelete = try await index.refresh()
        XCTAssertEqual(afterDelete.notes.map(\.id), ["Second.md"])
        XCTAssertNotEqual(afterDelete.revision, initial.revision)
    }

    func testSwitchingVaultClearsPriorIndex() async throws {
        let firstRoot = try temporaryDirectory()
        let secondRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        try write("# First", to: firstRoot.appendingPathComponent("First.md"))
        try write("# Second", to: secondRoot.appendingPathComponent("Second.md"))
        let index = VaultIndexService()
        _ = try await index.connect(firstRoot)
        let switched = try await index.connect(secondRoot)
        XCTAssertEqual(switched.notes.map(\.id), ["Second.md"])
        let switchedMetrics = await index.metrics()
        XCTAssertEqual(switchedMetrics.reparsedNoteCount, 1)
    }

    func testVaultSkipsHiddenAttachmentsAndSymlinkEscapes() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try write("# Visible", to: root.appendingPathComponent("Visible.md"))
        try write("# Hidden", to: root.appendingPathComponent(".private/Hidden.md"))
        try write("binary", to: root.appendingPathComponent("attachment.png"))
        let secret = outside.appendingPathComponent("Secret.md")
        try write("# Secret", to: secret)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Escape.md"), withDestinationURL: secret)

        let index = VaultIndexService()
        let snapshot = try await index.connect(root)
        XCTAssertEqual(snapshot.notes.map(\.id), ["Visible.md"])
        do {
            _ = try await index.readNote(id: "../Secret.md")
            XCTFail("Expected path escape to be blocked")
        } catch let error as VaultIndexError {
            XCTAssertEqual(error, .pathEscapesVault)
        }
    }

    func testVaultRejectsUnavailableFolder() async {
        let index = VaultIndexService()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await index.connect(missing)
            XCTFail("Expected unavailable vault to fail")
        } catch let error as VaultIndexError {
            XCTAssertEqual(error, .invalidVault)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveCreatesMOMOFolderAndNeverOverwrites() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = VaultIndexService()
        _ = try await index.connect(root)

        let (first, firstSnapshot) = try await index.save(title: "Brain Note", body: "First body")
        let (second, secondSnapshot) = try await index.save(title: "Brain Note", body: "Second body")
        XCTAssertEqual(first.lastPathComponent, "Brain Note.md")
        XCTAssertEqual(second.lastPathComponent, "Brain Note 2.md")
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "MOMO")
        XCTAssertEqual(firstSnapshot.notes.count, 1)
        XCTAssertEqual(secondSnapshot.notes.count, 2)
        XCTAssertTrue(try String(contentsOf: first, encoding: .utf8).contains("First body"))
        XCTAssertTrue(try String(contentsOf: second, encoding: .utf8).contains("Second body"))
    }

    func testLargeVaultIncrementalProfileReparsesNothingWhenUnchanged() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<1_000 {
            try write("# Note \(index)\n[[Note \((index + 1) % 1_000)]] #profile", to: root.appendingPathComponent("Note \(index).md"))
        }
        let service = VaultIndexService()
        _ = try await service.connect(root)
        let initial = await service.metrics()
        _ = try await service.refresh()
        let unchanged = await service.metrics()
        XCTAssertEqual(initial.indexedNoteCount, 1_000)
        XCTAssertEqual(initial.reparsedNoteCount, 1_000)
        XCTAssertEqual(unchanged.indexedNoteCount, 1_000)
        XCTAssertEqual(unchanged.reparsedNoteCount, 0)
        print("Vault profile: initial=\(initial.duration)s unchanged=\(unchanged.duration)s notes=\(unchanged.indexedNoteCount)")
    }

    func testOllamaCachesBySourceRevisionAndKeepsRequestsBounded() async throws {
        let client = MockOllamaClient()
        let service = OllamaService(client: client, refreshInterval: 0)
        await service.refresh(force: true)
        XCTAssertEqual(service.selectedModel, "momo-local")

        let first = await service.complete(prompt: String(repeating: "x", count: 20_000), sourceRevision: "r1")
        let cached = await service.complete(prompt: String(repeating: "x", count: 20_000), sourceRevision: "r1")
        let firstCount = await client.count()
        XCTAssertEqual(first, "answer-1")
        XCTAssertEqual(cached, "answer-1")
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(service.statusText, "ANSWER READY · CACHED")

        let revised = await service.complete(prompt: String(repeating: "x", count: 20_000), sourceRevision: "r2")
        let revisedCount = await client.count()
        XCTAssertEqual(revised, "answer-2")
        XCTAssertEqual(revisedCount, 2)
    }

    func testOllamaDistinguishesTimeoutMalformedAndMissingModel() async {
        let timeoutClient = MockOllamaClient(behavior: .timeout)
        let timeoutService = OllamaService(client: timeoutClient, refreshInterval: 0)
        await timeoutService.refresh(force: true)
        let timedOut = await timeoutService.complete(prompt: "question")
        XCTAssertNil(timedOut)
        XCTAssertEqual(timeoutService.state, .timedOut)

        let malformedClient = MockOllamaClient(behavior: .malformed)
        let malformedService = OllamaService(client: malformedClient, refreshInterval: 0)
        await malformedService.refresh(force: true)
        let malformed = await malformedService.complete(prompt: "question")
        XCTAssertNil(malformed)
        XCTAssertEqual(malformedService.state, .failed)

        let missingClient = MockOllamaClient(models: [])
        let missingService = OllamaService(client: missingClient, refreshInterval: 0)
        await missingService.refresh(force: true)
        let missing = await missingService.complete(prompt: "question")
        XCTAssertNil(missing)
        XCTAssertEqual(missingService.state, .missingModel)
    }

    func testOllamaUsesMomoBrandedThinkingCopy() async {
        let client = MockOllamaClient(behavior: .delayed)
        let service = OllamaService(client: client, refreshInterval: 0)
        XCTAssertEqual(service.statusText, "CHECKING LOCAL MODEL")
        await service.refresh(force: true)
        XCTAssertEqual(service.statusText, "LOCAL MODEL READY · 1")
        let task = Task { await service.complete(prompt: "first") }
        while !service.isGenerating { await Task.yield() }
        XCTAssertEqual(service.statusText, "MOMO THINKING")
        service.cancel()
        _ = await task.value
        XCTAssertEqual(service.statusText, "MOMO CANCELLED")
        XCTAssertFalse(service.statusText.localizedCaseInsensitiveContains("ollama"))
    }

    func testOllamaAllowsOneGenerationAndCanCancelIt() async {
        let client = MockOllamaClient(behavior: .delayed)
        let service = OllamaService(client: client, refreshInterval: 0)
        await service.refresh(force: true)
        let first = Task { await service.complete(prompt: "first") }
        while !service.isGenerating { await Task.yield() }
        let second = await service.complete(prompt: "second")
        XCTAssertNil(second)
        service.cancel()
        let firstResult = await first.value
        XCTAssertNil(firstResult)
        XCTAssertEqual(service.state, .cancelled)
        XCTAssertFalse(service.isGenerating)
        let count = await client.count()
        XCTAssertEqual(count, 1)
    }

    func testOllamaModelSelectionSurvivesRefreshOnlyWhileAvailable() async {
        let client = MockOllamaClient(models: ["alpha", "beta"])
        let service = OllamaService(client: client, refreshInterval: 0)
        await service.refresh(force: true)
        service.selectedModel = "beta"
        await service.refresh(force: true)
        XCTAssertEqual(service.selectedModel, "beta")
        await client.setModels(["alpha"])
        await service.refresh(force: true)
        XCTAssertEqual(service.selectedModel, "alpha")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MomoBrainTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
