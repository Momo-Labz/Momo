import Combine
import Foundation
import UserNotifications

@MainActor
final class RelayStore: ObservableObject {
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
    private var notifiedUrgentIDs = Set<String>()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            status = .demo
            connection = .live
            return
        }
        if let saved = RelayKeychain.load() {
            credential = saved
            pairAddress = saved.pairingAddress
            RelayKeychain.save(saved)
            startPolling()
        }
    }

    deinit { pollTask?.cancel() }

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
        RelayKeychain.clear()
    }

    func refresh() async { await fetch() }

    static func statusURL(from input: String) -> URL? {
        RelayCredential(pairingAddress: input)?.statusURL
    }

    private func startPolling() {
        pollTask?.cancel()
        connection = .connecting
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetch()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func fetch() async {
        guard let credential else { return }
        do {
            var request = URLRequest(url: credential.statusURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(RelayStatus.self, from: data)
            let newUrgent = decoded.sessions.filter(\.urgent).filter { !notifiedUrgentIDs.contains($0.id) }
            status = decoded
            connection = .live
            notifiedUrgentIDs.formUnion(decoded.sessions.filter(\.urgent).map(\.id))
            if !newUrgent.isEmpty { await notify(for: newUrgent) }
        } catch {
            connection = .offline("Your Mac is not reachable. Keep both devices on the same network and Desk Display enabled.")
        }
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
