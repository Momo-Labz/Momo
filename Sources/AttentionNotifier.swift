import Foundation
import UserNotifications

@MainActor
final class AttentionNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationLabel = "Off"
    @Published private(set) var completedSessions: [AgentSession] = []
    private var notified = Set<String>()
    private var currentSessions: [String: AgentSession] = [:]
    private var knownStates: [String: AgentAttention] = [:]

    private enum Category {
        static let ret = "MOMO_RETURN"
        static let reset = "MOMO_RESET"
        static let open = "MOMO_OPEN_REPLY"
    }

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // A visible button so the alert states the action it performs.
        let open = UNNotificationAction(identifier: Category.open, title: "Open reply", options: [.foreground])
        let cont = UNNotificationAction(identifier: Category.open, title: "Continue chat", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.ret, actions: [open], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.reset, actions: [cont], intentIdentifiers: [], options: [])
        ])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        guard action == UNNotificationDefaultActionIdentifier || action == Category.open else { return }
        await MainActor.run {
            guard let session = self.currentSessions[identifier] else { return }
            NotificationCenter.default.post(name: .showCommandPalette, object: session)
        }
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorizationLabel = granted ? "On" : "Not allowed"
        return granted
    }

    func update(snapshots: [ProviderSnapshot], enabled: Bool, now: Date = .now) {
        let sessions = snapshots.flatMap(\.sessions)
        let newlyCompleted = sessions.filter { session in
            session.attention == .completed && knownStates[session.id] != nil && knownStates[session.id] != .completed
        }
        for session in sessions { knownStates[session.id] = session.attention }
        completedSessions = (completedSessions + newlyCompleted).filter { now.timeIntervalSince($0.updatedAt) < 900 }

        guard enabled else {
            currentSessions.removeAll()
            notified.removeAll()
            authorizationLabel = "Off"
            return
        }
        authorizationLabel = "On"

        let urgent = sessions.filter {
            $0.attention.isUrgent && ($0.isRunning || now.timeIntervalSince($0.updatedAt) < 300)
        }
        // A recorded window that reset within the last half hour: the chat can move again.
        let reopened = sessions.filter { session in
            guard !session.isRunning else { return false }
            return Self.justReset(session, now: now) != nil
        }

        var live: [String: AgentSession] = [:]
        for session in urgent { live["\(session.id)|\(session.attention.rawValue)"] = session }
        for session in reopened {
            guard let reset = Self.justReset(session, now: now) else { continue }
            live["\(session.id)|reset|\(Int(reset.timeIntervalSince1970))"] = session
        }
        currentSessions = live
        notified.formIntersection(Set(live.keys))

        for (identifier, session) in live {
            guard notified.insert(identifier).inserted else { continue }
            let content = UNMutableNotificationContent()
            if identifier.contains("|reset|") {
                let auto = AutoResumeService.supportsUnattendedResume(session)
                content.title = "\(session.provider.name) usage window reset"
                content.body = auto
                    ? "\(session.title) can continue. MOMO continues it automatically when auto-resume is on."
                    : "\(session.title) can continue. Open it to send the next turn."
                content.categoryIdentifier = Category.reset
            } else {
                content.title = session.attention == .failed ? "\(session.provider.name) hit a problem" : "\(session.provider.name) needs you"
                content.body = session.attentionReason ?? session.title
                content.categoryIdentifier = Category.ret
            }
            // Folder is the second half of a conversation's identity.
            content.subtitle = "\(session.title) · \(session.project)"
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }

        for session in newlyCompleted {
            let content = UNMutableNotificationContent()
            content.title = "(session.provider.name) finished"
            content.body = session.title
            content.subtitle = session.project
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "completed|\(session.id)|\(Int(session.updatedAt.timeIntervalSince1970))", content: content, trigger: nil))
        }
    }

    /// The reset time of a recorded window that opened within the last 30 minutes.
    static func justReset(_ session: AgentSession, now: Date) -> Date? {
        session.recordedQuotaWindows.compactMap(\.resetsAt)
            .filter { $0 <= now && now.timeIntervalSince($0) < 1_800 }
            .max()
    }
}
