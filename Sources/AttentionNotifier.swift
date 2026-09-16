import Foundation
import UserNotifications

@MainActor
final class AttentionNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationLabel = "Off"
    @Published private(set) var completedSessions: [AgentSession] = []
    let policyStore: NotificationPolicyStore
    private var notified = Set<String>()
    private var currentSessions: [String: AgentSession] = [:]
    private var knownStates: [String: AgentAttention] = [:]
    private var hasSeededState = false

    private enum Category {
        static let ret = "MOMO_RETURN"
        static let reset = "MOMO_RESET"
        static let open = "MOMO_OPEN_REPLY"
    }

    init(policyStore: NotificationPolicyStore? = nil) {
        self.policyStore = policyStore ?? NotificationPolicyStore()
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
        let policy = policyStore.policy
        let newlyCompleted = sessions.filter { session in
            let key = Self.sessionIdentity(session)
            return session.attention == .completed && knownStates[key] != nil && knownStates[key] != .completed
        }
        for session in sessions { knownStates[Self.sessionIdentity(session)] = session.attention }
        completedSessions = (completedSessions + newlyCompleted).filter { now.timeIntervalSince($0.updatedAt) < 900 }

        guard enabled, policy.isEnabled else {
            currentSessions.removeAll()
            notified.removeAll()
            knownStates.removeAll()
            hasSeededState = false
            authorizationLabel = "Off"
            return
        }
        authorizationLabel = "On"

        let urgent = sessions.filter { session in
            let eventEnabled = session.attention == .failed ? policy.notifyOnFailure : policy.notifyOnNeedsInput
            return session.attention.isUrgent && eventEnabled
                && (session.isRunning || now.timeIntervalSince(session.updatedAt) < 300)
        }
        // A recorded window that reset within the last half hour: the chat can move again.
        let reopened = sessions.filter { session in
            guard policy.notifyOnUsageReset, !session.isRunning else { return false }
            return Self.justReset(session, now: now) != nil
        }

        var live: [String: AgentSession] = [:]
        for session in urgent { live["\(Self.sessionIdentity(session))|\(session.attention.rawValue)"] = session }
        for session in reopened {
            guard let reset = Self.justReset(session, now: now) else { continue }
            live["\(Self.sessionIdentity(session))|reset|\(Int(reset.timeIntervalSince1970))"] = session
        }
        currentSessions = live
        notified.formIntersection(Set(live.keys))

        let usageObservations = snapshots.flatMap(Self.usageObservations)
        if !hasSeededState {
            notified.formUnion(live.keys)
            for observation in usageObservations { _ = policyStore.newMilestones(for: observation, now: now) }
            hasSeededState = true
            return
        }

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
                MomoAlertPresenter.shared.trigger(.sessionStopped)
            } else {
                content.title = session.attention == .failed ? "\(session.provider.name) hit a problem" : "\(session.provider.name) needs you"
                content.body = session.attentionReason ?? session.title
                content.categoryIdentifier = Category.ret
                MomoAlertPresenter.shared.trigger(session.attention == .failed ? .failure : .needsYou)
            }
            // Folder is the second half of a conversation's identity.
            content.subtitle = "\(session.title) · \(session.project)"
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }

        if policy.notifyOnCompletion {
            for session in newlyCompleted {
                let content = UNMutableNotificationContent()
                content.title = "\(session.provider.name) finished"
                content.body = session.title
                content.subtitle = session.project
                content.sound = .default
                let identifier = "completed|\(Self.sessionIdentity(session))|\(Int(session.updatedAt.timeIntervalSince1970))"
                currentSessions[identifier] = session
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                MomoAlertPresenter.shared.trigger(.sessionStopped)
            }
        }

        for observation in usageObservations {
            for threshold in policyStore.newMilestones(for: observation, now: now) {
                let content = UNMutableNotificationContent()
                content.title = threshold == 100
                    ? "\(observation.provider.name) usage limit reached"
                    : "\(observation.provider.name) usage reached \(threshold)%"
                content.body = observation.resetsAt.map { "Resets \($0.formatted())" }
                    ?? "No reset time was recorded."
                content.sound = .default
                let cycle = observation.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "open"
                let identifier = "usage|\(observation.provider.rawValue)|\(observation.metric.lowercased())|\(threshold)|\(cycle)"
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                MomoAlertPresenter.shared.trigger(.usageLow)
            }
        }
    }

    /// The reset time of a recorded window that opened within the last 30 minutes.
    static func justReset(_ session: AgentSession, now: Date) -> Date? {
        session.recordedQuotaWindows.compactMap(\.resetsAt)
            .filter { $0 <= now && now.timeIntervalSince($0) < 1_800 }
            .max()
    }

    static func sessionIdentity(_ session: AgentSession) -> String {
        "\(session.provider.rawValue)|\(session.conversationID ?? session.id)"
    }

    private static func usageObservations(_ snapshot: ProviderSnapshot) -> [ProviderUsageObservation] {
        let windows = snapshot.recordedQuotas.isEmpty
            ? snapshot.recordedQuota.map { [$0] } ?? []
            : snapshot.recordedQuotas
        return windows.map { window in
            ProviderUsageObservation(
                provider: snapshot.provider,
                metric: window.durationLabel,
                percentage: Int(window.percent.rounded()),
                resetsAt: window.resetsAt,
                capturedAt: window.observedAt,
                freshness: TrackingCache.acceptedObservationFreshness,
                provenance: .providerEvent
            )
        }
    }
}
