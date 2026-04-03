import UserNotifications
import Combine
import UIKit

class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private var cancellables = Set<AnyCancellable>()
    private var isAppActive: Bool { UIApplication.shared.applicationState == .active }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted { scheduleDailyReminder() }
            return granted
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Start listening to WebSocket events

    func startListening() {
        cancellables.removeAll()

        // New chat message
        WebSocketManager.shared.onChatMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                guard let self, !self.isAppActive else { return }
                guard msg.fromId != AppState.shared.currentUID else { return }
                let name = msg.fromName ?? "Someone"
                let body = msg.activityTitle ?? msg.text ?? L10n.t("sent")
                self.send(
                    title: name,
                    body: body,
                    id: "chat_\(msg.id)"
                )
            }
            .store(in: &cancellables)

        // Friend request
        WebSocketManager.shared.onFriendRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.send(
                    title: "PAKT",
                    body: "\(event.fromName) \(L10n.t("wants_friend"))",
                    id: "friend_req_\(event.requestId)"
                )
            }
            .store(in: &cancellables)

        // Group invitation
        WebSocketManager.shared.onInvitation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let name = event.fromName ?? "Someone"
                let group = event.groupName ?? L10n.t("groups")
                self.send(
                    title: name,
                    body: "\(L10n.t("invited_to_group")): \(group)",
                    id: "invite_\(event.invitationId)"
                )
            }
            .store(in: &cancellables)

        // Group update (member joined, challenge started)
        WebSocketManager.shared.onGroupUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event.type {
                case "started":
                    let groupName = AppState.shared.groups.first(where: { $0.id.uuidString == event.groupId })?.name ?? L10n.t("groups")
                    self.send(
                        title: "🔥 \(groupName)",
                        body: L10n.t("pakt_activated"),
                        id: "group_started_\(event.groupId)"
                    )
                case "member_joined":
                    let memberName = event.member?.username ?? "Someone"
                    let groupName = AppState.shared.groups.first(where: { $0.id.uuidString == event.groupId })?.name ?? ""
                    self.send(
                        title: groupName,
                        body: "\(memberName) \(L10n.t("sign_the_pakt").lowercased())",
                        id: "member_joined_\(event.groupId)_\(event.member?.userId ?? "")"
                    )
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Chat response (someone responded to your activity proposal)
        WebSocketManager.shared.onChatResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                guard event.fromId != AppState.shared.currentUID else { return }
                let name = event.fromName ?? "Someone"
                let response = ProposalResponse(rawValue: event.response)?.label ?? event.response
                self.send(
                    title: name,
                    body: response,
                    id: "chat_resp_\(event.id)"
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Send local notification

    private func send(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Daily reminder

    func scheduleDailyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])

        let content = UNMutableNotificationContent()
        content.title = "PAKT"
        content.body = "How was your day? Check your screen time."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        center.add(request)
    }

    func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }
}
