import SwiftUI

/// Friend + group picker to share an event via 1:1 chat or group chat.
/// Sends via POST /v1/chat/event (1:1) or POST /v1/groupchat/{id}/event (group).
struct ShareEventToFriendSheet: View {
    let eventId: String
    let eventTitle: String

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fm = FriendManager.shared

    @State private var sendingToId: String?
    @State private var sentToIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlurb

                    // Groups section
                    if !appState.groups.isEmpty {
                        sectionTitle("Groups")
                        VStack(spacing: 6) {
                            ForEach(appState.groups, id: \.id) { group in
                                groupRow(group)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }

                    // Friends section
                    sectionTitle("Friends")
                    if fm.friends.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 28))
                                .foregroundColor(Theme.textFaint)
                            Text("Add friends to share events with")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(fm.friends, id: \.id) { friend in
                                friendRow(friend)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 40)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.red)
                        .padding(10)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Share event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBlurb: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eventTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.text)
                .lineLimit(2)
            Text("Send to a friend or group")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .foregroundColor(Theme.textFaint)
            .tracking(1.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    // MARK: - Group row

    private func groupRow(_ group: Group) -> some View {
        let gid = "g_" + group.id.uuidString
        let sending = sendingToId == gid
        let sent = sentToIds.contains(gid)
        return Button {
            Task { await shareToGroup(group) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.blue)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("\(group.members.count) membres")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                if sending {
                    ProgressView()
                } else if sent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.green)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(Theme.textMuted)
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sent ? Theme.green.opacity(0.08) : Theme.bgCard)
            )
        }
        .buttonStyle(.plain)
        .disabled(sent || sending)
    }

    // MARK: - Friend row

    private func friendRow(_ friend: AppUser) -> some View {
        let sending = sendingToId == friend.id
        let sent = sentToIds.contains(friend.id)
        return Button {
            Task { await shareToFriend(friend) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.bgCard)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(friend.firstName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                    )
                Text(friend.firstName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if sending {
                    ProgressView()
                } else if sent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.green)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(Theme.textMuted)
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sent ? Theme.green.opacity(0.08) : Theme.bgCard)
            )
        }
        .buttonStyle(.plain)
        .disabled(sent || sending)
    }

    // MARK: - Actions

    private func shareToFriend(_ friend: AppUser) async {
        guard sendingToId == nil, !sentToIds.contains(friend.id) else { return }
        sendingToId = friend.id
        errorMessage = nil
        defer { sendingToId = nil }
        do {
            try await APIClient.shared.sendChatEvent(toId: friend.id, eventId: eventId)
            sentToIds.insert(friend.id)
        } catch {
            errorMessage = "Error:\(error.localizedDescription)"
        }
    }

    private func shareToGroup(_ group: Group) async {
        let gid = "g_" + group.id.uuidString
        guard sendingToId == nil, !sentToIds.contains(gid) else { return }
        sendingToId = gid
        errorMessage = nil
        defer { sendingToId = nil }
        do {
            try await APIClient.shared.sendGroupChatEvent(groupId: group.id.uuidString, eventId: eventId)
            sentToIds.insert(gid)
        } catch {
            errorMessage = "Error:\(error.localizedDescription)"
        }
    }
}
