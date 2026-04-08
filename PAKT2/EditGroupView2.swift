import SwiftUI

struct EditGroupView: View {
    let group: Group
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var fm = FriendManager.shared

    @State private var name          : String            = ""
    @State private var showDelete    = false
    @State private var showLeave     = false
    @State private var saved         = false
    @State private var codeCopied    = false
    @State private var invitedIds    : Set<String>       = []

    var isCreator: Bool {
        let uid = appState.currentUID
        guard !uid.isEmpty, !group.creatorId.isEmpty else { return false }
        return group.creatorId == uid
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 18)).foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text(L10n.t("edit_group")).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.textMuted)
                    Spacer()
                    Image(systemName: "xmark").opacity(0).font(.system(size: 18))
                }
                .padding(.horizontal, 24).padding(.top, 56).padding(.bottom, 32)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {

                        // Member avatars
                        HStack(spacing: -10) {
                            ForEach(Array(group.members.prefix(5).enumerated()), id: \.offset) { i, member in
                                AvatarView(name: member.name, size: 40, color: Theme.textMuted,
                                           uid: member.uid, isMe: appState.isMe(member))
                                    .environmentObject(appState)
                                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                                    .zIndex(Double(5 - i))
                            }
                        }

                        // Group name
                        if isCreator {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.t("group_name_label"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.textFaint).tracking(1.6)
                                TextField("", text: $name)
                                    .font(.system(size: 26, weight: .bold)).foregroundColor(Theme.text)
                                Rectangle().fill(Theme.border).frame(height: 1)
                            }
                            .padding(.horizontal, 24)
                        }

                        // MARK: - Members list
                        membersSection

                        // Challenge settings (locked)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.t("challenge_settings"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textFaint).tracking(1.6)
                                .padding(.horizontal, 24)
                            VStack(spacing: 0) {
                                lockedRow(label: L10n.t("goal"),     value: "\(formatTime(group.goalMinutes)) / day")
                                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                                lockedRow(label: L10n.t("mode_label"),     value: group.mode.displayName)
                                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                                lockedRow(label: L10n.t("duration"), value: group.duration.displayName)
                            }
                            .liquidGlass(cornerRadius: 12)
                            .padding(.horizontal, 24)
                            HStack(spacing: 6) {
                                Image(systemName: "lock").font(.system(size: 13)).foregroundColor(Theme.textFaint)
                                Text(L10n.t("settings_locked"))
                                    .font(.system(size: 13)).foregroundColor(Theme.textFaint)
                            }
                            .padding(.horizontal, 24)
                        }

                        // Group code
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.t("group_code_label"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textFaint).tracking(1.6)
                                .padding(.horizontal, 24)
                            Button(action: {
                                UIPasteboard.general.string = group.code
                                withAnimation { codeCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { codeCopied = false } }
                            }) {
                                HStack {
                                    Text(group.code)
                                        .font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text).tracking(3)
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc").font(.system(size: 15))
                                        Text(codeCopied ? L10n.t("copied") : L10n.t("copy")).font(.system(size: 14))
                                    }
                                    .foregroundColor(codeCopied ? Theme.green : Theme.textFaint)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .liquidGlass(cornerRadius: 12)
                            }
                            .padding(.horizontal, 24)
                        }

                        // Invite friends — only for pending groups
                        let memberUids = Set(group.members.map { $0.uid })
                        let inviteable = fm.friends.filter { !memberUids.contains($0.id) }
                        if group.isPending && !inviteable.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.t("invite_friends"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.textFaint).tracking(1.6)
                                    .padding(.horizontal, 24)
                                VStack(spacing: 0) {
                                    ForEach(Array(inviteable.enumerated()), id: \.element.id) { i, friend in
                                        HStack(spacing: 12) {
                                            AvatarView(name: friend.firstName, size: 40, color: Theme.textMuted,
                                                       uid: friend.id, isMe: false)
                                                .environmentObject(appState)
                                            Text(friend.firstName)
                                                .font(.system(size: 17, weight: .medium)).foregroundColor(Theme.text)
                                            Spacer()
                                            if invitedIds.contains(friend.id) {
                                                Button(action: {
                                                    InvitationManager.shared.cancelInvitation(toUserId: friend.id, groupId: group.id.uuidString)
                                                    invitedIds.remove(friend.id)
                                                }) {
                                                    HStack(spacing: 5) {
                                                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                                                        Text(L10n.t("cancel_invite")).font(.system(size: 14, weight: .medium))
                                                    }
                                                    .foregroundColor(Theme.red)
                                                    .padding(.vertical, 7).padding(.horizontal, 12)
                                                    .background(Theme.red.opacity(0.08)).cornerRadius(8)
                                                }
                                            } else {
                                                Button(action: {
                                                    Task { try? await APIClient.shared.sendInvitation(groupID: group.id.uuidString, toID: friend.id) }
                                                    invitedIds.insert(friend.id)
                                                }) {
                                                    HStack(spacing: 5) {
                                                        Image(systemName: "person.badge.plus").font(.system(size: 13))
                                                        Text(L10n.t("invite_btn")).font(.system(size: 14, weight: .medium))
                                                    }
                                                    .foregroundColor(Theme.textMuted)
                                                    .padding(.vertical, 7).padding(.horizontal, 12)
                                                    .liquidGlass(cornerRadius: 8)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 12)
                                        if i < inviteable.count - 1 {
                                            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 56)
                                        }
                                    }
                                }
                                .liquidGlass(cornerRadius: 12)
                                .padding(.horizontal, 24)
                            }
                        }

                        // Actions
                        VStack(spacing: 12) {
                            if group.isPending && isCreator {
                                Button(action: { showDelete = true }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "trash").font(.system(size: 16))
                                        Text(L10n.t("delete_group")).font(.system(size: 16))
                                    }
                                    .foregroundColor(Theme.red).frame(maxWidth: .infinity)
                                    .padding(.vertical, 16).background(Theme.red.opacity(0.06)).cornerRadius(14)
                                }
                            }

                            if !isCreator {
                                Button(action: { showLeave = true }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16))
                                        Text(L10n.t("leave_group")).font(.system(size: 16))
                                    }
                                    .foregroundColor(Theme.red).frame(maxWidth: .infinity)
                                    .padding(.vertical, 16).background(Theme.red.opacity(0.06)).cornerRadius(14)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 32)
                }

                Spacer()

                if isCreator {
                    PrimaryButton(label: saved ? L10n.t("saved") + " ✓" : L10n.t("save_changes")) { saveChanges() }
                        .padding(.horizontal, 24).padding(.bottom, 52)
                        .opacity(name.isEmpty ? 0.35 : 1).disabled(name.isEmpty)
                }
            }
        }
        .onAppear {
            name = group.name
        }
        .confirmationDialog("\(L10n.t("delete")) \"\(group.name)\"?", isPresented: $showDelete, titleVisibility: .visible) {
            Button(L10n.t("delete_group"), role: .destructive) { appState.deleteGroup(group); dismiss() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: { Text(L10n.t("delete_group_warn")) }
        .confirmationDialog("\(L10n.t("leave_group")) \"\(group.name)\"?", isPresented: $showLeave, titleVisibility: .visible) {
            Button(L10n.t("leave_group"), role: .destructive) { appState.leaveGroup(group); dismiss() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: { Text(L10n.t("leave_group_warn")) }
    }

    // MARK: - Members section

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("members").uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textFaint).tracking(1.6)
                Spacer()
                Text("\(group.members.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 0) {
                ForEach(Array(group.members.enumerated()), id: \.element.id) { i, member in
                    HStack(spacing: 12) {
                        AvatarView(name: member.name, size: 40, color: Theme.textMuted,
                                   uid: member.uid, isMe: appState.isMe(member))
                            .environmentObject(appState)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Theme.text)
                                if member.uid == group.creatorId {
                                    Text(L10n.t("admin"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.green)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.green.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                if appState.isMe(member) {
                                    Text(L10n.t("you"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.textFaint)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.bgWarm)
                                        .cornerRadius(4)
                                }
                            }
                            Text(formatTime(member.todayMinutes) + " today")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textFaint)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)

                    if i < group.members.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 68)
                    }
                }
            }
            .liquidGlass(cornerRadius: 12)
            .padding(.horizontal, 24)
        }
    }

    func lockedRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundColor(Theme.textMuted)
            Spacer()
            Text(value).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.textFaint)
            Image(systemName: "lock").font(.system(size: 13)).foregroundColor(Theme.textFaint).padding(.leading, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    func saveChanges() {
        var updated = group; updated.name = name
        appState.updateGroup(updated)
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}
