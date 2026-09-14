import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class RelayStore: ObservableObject {
    private enum PollResult {
        case changed
        case unchanged
        case failed

        var nextDelay: Duration {
            switch self {
            case .changed: return .seconds(15)
            case .unchanged, .failed: return .seconds(60)
            }
        }
    }

    private static let latestSupportedSchema = 2
    enum ConnectionState: Equatable {
        case unpaired
        case connecting
        case live
        case offline(String)

        var label: String {
            switch self {
            case .unpaired: return "UNPAIRED"
            case .connecting: return "CONNECTING"
            case .live: return "LIVE"
            case .offline: return "OFFLINE"
            }
        }
    }

    @Published var pairAddress = ""
    @Published private(set) var status: RelayStatus?
    @Published private(set) var connection: ConnectionState = .unpaired

    private var credential: RelayCredential?
    private var pollTask: Task<Void, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var notifiedUrgentIDs = Set<String>()
    private var statusETag: String?
    private var lastPayload: Data?

    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            status = .demo
            connection = .live
            return
        }
        observeLifecycle()
        if let saved = RelayKeychain.load() {
            credential = saved
            pairAddress = saved.pairingAddress
            RelayKeychain.save(saved)
            startPolling()
        }
    }

    deinit {
        pollTask?.cancel()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func connect() {
        guard let nextCredential = RelayCredential(pairingAddress: pairAddress) else {
            connection = .offline("Paste the full pairing address from MOMO on your Mac.")
            return
        }
        credential = nextCredential
        pairAddress = nextCredential.pairingAddress
        RelayKeychain.save(nextCredential)
        startPolling()
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        credential = nil
        status = nil
        pairAddress = ""
        connection = .unpaired
        statusETag = nil
        lastPayload = nil
        RelayKeychain.clear()
    }

    func refresh() async { _ = await fetch() }

    static func statusURL(from input: String) -> URL? {
        RelayCredential(pairingAddress: input)?.statusURL
    }

    private func startPolling() {
        pollTask?.cancel()
        guard UIApplication.shared.applicationState == .active else { return }
        connection = .connecting
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let result = await self.fetch()
                try? await Task.sleep(for: result.nextDelay)
            }
        }
    }

    private func fetch() async -> PollResult {
        guard let credential else { return .failed }
        do {
            var request = URLRequest(url: credential.statusURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.momo.relay+json; version=2, application/json;q=0.9", forHTTPHeaderField: "Accept")
            request.setValue("2", forHTTPHeaderField: "X-Relay-Client-Schema")
            if let statusETag { request.setValue(statusETag, forHTTPHeaderField: "If-None-Match") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if http.statusCode == 304 {
                connection = .live
                return .unchanged
            }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(RelayStatus.self, from: data)
            guard (decoded.schemaVersion ?? 1) <= Self.latestSupportedSchema else {
                connection = .offline("This Relay version needs a newer MOMO RELAY app.")
                return .failed
            }
            let newUrgent = decoded.sessions.filter(\.urgent).filter { !notifiedUrgentIDs.contains($0.id) }
            status = decoded
            statusETag = http.value(forHTTPHeaderField: "ETag")
            let changed = lastPayload != data
            lastPayload = data
            connection = .live
            notifiedUrgentIDs.formUnion(decoded.sessions.filter(\.urgent).map(\.id))
            if !newUrgent.isEmpty { await notify(for: newUrgent) }
            return changed ? .changed : .unchanged
        } catch {
            connection = .offline("Your Mac is not reachable. Keep both devices on the same network and Desk Display enabled.")
            return .failed
        }
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.startPolling() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.pollTask?.cancel()
                    self?.pollTask = nil
                }
            }
        ]
    }

    private func notify(for sessions: [RelaySession]) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = sessions.count == 1 ? "An agent needs you" : "\(sessions.count) agents need you"
        content.body = sessions.first?.title ?? "Open MOMO RELAY to clear the return queue."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
