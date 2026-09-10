import Foundation
import UserNotifications

@MainActor
final class AttentionNotifier: ObservableObject {
    @Published private(set) var authorizationLabel = "Off"
    private var notified = Set<String>()

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorizationLabel = granted ? "On" : "Not allowed"
        return granted
    }

    func update(snapshots: [ProviderSnapshot], enabled: Bool) {
        guard enabled else {
            authorizationLabel = "Off"
            return
        }
        authorizationLabel = "On"
        let urgent = snapshots.flatMap(\.sessions).filter {
            $0.attention.isUrgent && ($0.isRunning || Date().timeIntervalSince($0.updatedAt) < 300)
        }
        let currentIDs = Set(urgent.map { "\($0.id)|\($0.attention.rawValue)" })
        notified.formIntersection(currentIDs)
        for session in urgent {
            let notificationID = "\(session.id)|\(session.attention.rawValue)"
            guard notified.insert(notificationID).inserted else { continue }
            let content = UNMutableNotificationContent()
            content.title = session.attention == .failed ? "\(session.provider.name) hit a problem" : "\(session.provider.name) needs you"
            content.subtitle = session.project
            content.body = session.attentionReason ?? session.title
            content.sound = .default
            let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
