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

    private var statusURL: URL?
    private var pollTask: Task<Void, Never>?
    private var notifiedUrgentIDs = Set<String>()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            status = .demo
            connection = .live
            return
        }
        if let saved = RelayKeychain.load(), let url = URL(string: saved) {
            pairAddress = saved
            statusURL = url
            startPolling()
        }
    }

    deinit { pollTask?.cancel() }

    func connect() {
        guard let url = Self.statusURL(from: pairAddress) else {
            connection = .offline("Paste the full pairing address from BAR BOY on your Mac.")
            return
        }
        statusURL = url
        pairAddress = url.absoluteString
        RelayKeychain.save(url.absoluteString)
        startPolling()
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        statusURL = nil
        status = nil
        pairAddress = ""
        connection = .unpaired
        RelayKeychain.clear()
    }

    func refresh() async { await fetch() }

    static func statusURL(from input: String) -> URL? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: cleaned),
              components.scheme == "http" || components.scheme == "https",
              components.host != nil,
              components.queryItems?.contains(where: { $0.name == "key" && !($0.value ?? "").isEmpty }) == true else { return nil }
        components.path = "/api/status"
        return components.url
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
        guard let statusURL else { return }
        do {
            var request = URLRequest(url: statusURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5
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
