import SwiftUI
import Combine

// MARK: - Invitation model

struct GroupInvitation: Identifiable, Codable {
    var id        : String
    var groupId   : String
    var groupName : String
    var groupMode : String
    var groupGoal : Int
    var groupStake: String
    var fromName  : String
    var fromId    : String
    var toId      : String
    var sentAt    : Date
    var status    : String

    init(groupId: String, groupName: String, groupMode: String, groupGoal: Int,
         groupStake: String = "For fun", fromName: String, fromId: String, toId: String) {
        self.id        = UUID().uuidString
        self.groupId   = groupId
        self.groupName = groupName
        self.groupMode = groupMode
        self.groupGoal = groupGoal
        self.groupStake = groupStake
        self.fromName  = fromName
        self.fromId    = fromId
        self.toId      = toId
        self.sentAt    = Date()
        self.status    = "pending"
    }
}

// MARK: - InvitationManager

final class InvitationManager: NSObject, ObservableObject {
    static let shared = InvitationManager()

    @Published var pending: [GroupInvitation] = []
    @Published var errorMessage: String? = nil

    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func startListening() {
        stopListening()
        // Initial fetch
        fetchInvitations()
        // Poll every 30 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetchInvitations()
        }

        // Listen to WebSocket events for real-time invitation updates
        WebSocketManager.shared.onInvitation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.fetchInvitations() // Reload from server
            }
            .store(in: &cancellables)
    }

    func stopListening() {
        pollTimer?.invalidate()
        pollTimer = nil
        cancellables.removeAll()
    }

    func fetchInvitations() {
        Task {
            do {
                let invitations = try await APIClient.shared.listInvitations()
                await MainActor.run {
                    self.pending = invitations.filter { $0.status == "pending" }.map { inv in
                        var g = GroupInvitation(
                            groupId: inv.groupId, groupName: inv.groupName,
                            groupMode: inv.groupMode, groupGoal: inv.groupGoal,
                            groupStake: inv.groupStake ?? "For fun",
                            fromName: inv.fromName, fromId: inv.fromId, toId: inv.toId
                        )
                        g.id = inv.id
                        g.sentAt = inv.sentAt
                        g.status = inv.status
                        return g
                    }
                }
            } catch {
                Log.d("[InvitationManager] fetchInvitations error: \(error)")
            }
        }
    }

    func sendInvitation(to user: AppUser, for group: Group) {
        guard let currentUser = AuthManager.shared.currentUser else { return }
        let inv = GroupInvitation(
            groupId: group.id.uuidString, groupName: group.name,
            groupMode: group.mode.rawValue, groupGoal: group.goalMinutes,
            groupStake: group.stake,
            fromName: currentUser.firstName, fromId: currentUser.id, toId: user.id
        )
        Task {
            do {
                try await APIClient.shared.sendInvitation(groupID: inv.groupId, toID: inv.toId)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func accept(_ inv: GroupInvitation, appState: AppState) {
        guard AuthManager.shared.currentUser != nil else { return }
        DispatchQueue.main.async { self.pending.removeAll { $0.id == inv.id } }
        Task {
            do {
                let apiGroup = try await APIClient.shared.acceptInvitation(id: inv.id)
                let group = apiGroup.toGroup()
                await MainActor.run {
                    appState.groups.removeAll { $0.id == group.id }
                    appState.groups.append(group)
                    appState.saveGroupsLocal()
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func decline(_ inv: GroupInvitation) {
        DispatchQueue.main.async { self.pending.removeAll { $0.id == inv.id } }
        Task {
            do {
                try await APIClient.shared.declineInvitation(id: inv.id)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelInvitation(toUserId: String, groupId: String) {
        // Find the invitation and decline it
        if let inv = pending.first(where: { $0.toId == toUserId && $0.groupId == groupId }) {
            decline(inv)
        }
    }
}

// MARK: - NotificationsView

struct NotificationsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var invManager = InvitationManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.t("notifications"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                                .frame(width: 36, height: 36).liquidGlass(cornerRadius: 10)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 28)

                    if invManager.pending.isEmpty {
                        emptyState
                    } else {
                        SectionTitle(text: L10n.t("pending_invitations"))
                        VStack(spacing: 12) {
                            ForEach(invManager.pending) { inv in invitationCard(inv) }
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer().frame(height: 60)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
    }

    var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundColor(Theme.textFaint)
            Text(L10n.t("no_notifs"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.text)
            Text(L10n.t("all_caught_up"))
                .font(.system(size: 15))
                .foregroundColor(Theme.textFaint)
        }
        .padding(.top, 80).padding(.horizontal, 40)
    }

    func invitationCard(_ inv: GroupInvitation) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.bgWarm).frame(width: 44, height: 44)
                    Text(String(inv.fromName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.textMuted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(inv.fromName)
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                    Text(L10n.t("invited_to_group"))
                        .font(.system(size: 14)).foregroundColor(Theme.textFaint)
                }
                Spacer()
            }

            // Group info
            VStack(alignment: .leading, spacing: 8) {
                Text(inv.groupName)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text)
                HStack(spacing: 8) {
                    Text(inv.groupMode.lowercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textFaint).tracking(0.8)
                    Text("\(L10n.t("goal")) \(formatTime(inv.groupGoal))\(L10n.t("per_day"))")
                        .font(.system(size: 14)).foregroundColor(Theme.textFaint)
                }
            }

            // Stake — prominent
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("stake_label"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textFaint).tracking(1.2)
                    Text(inv.groupStake)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.text)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.orange.opacity(0.06))
            .cornerRadius(12)

            HStack(spacing: 10) {
                Button(action: { invManager.decline(inv) }) {
                    Text(L10n.t("decline"))
                        .font(.system(size: 15, weight: .medium)).foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.bgWarm).cornerRadius(12)
                }
                Button(action: { invManager.accept(inv, appState: appState) }) {
                    Text(L10n.t("sign_the_pakt"))
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.text).cornerRadius(12)
                }
            }
        }
        .padding(20).liquidGlass(cornerRadius: 18)
    }

}
