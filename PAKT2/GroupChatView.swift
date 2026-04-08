import SwiftUI
import Combine

struct GroupChatView: View {
    let group: Group
    var inline: Bool = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = ActivityManager.shared
    @State private var textInput = ""
    @FocusState private var isTextFocused: Bool
    @State private var messageToDelete: ChatMessage? = nil
    @State private var showReportSheet = false
    @State private var reportedMessageId: String? = nil
    @State private var showGroupSettings = false
    @State private var localMessages: [ChatMessage] = []
    @State private var pollTimer: Timer? = nil
    @State private var selectedMember: AppUser? = nil

    var groupId: String { group.id.uuidString }
    var myUid: String { manager.myUid }
    var chatMessages: [ChatMessage] { localMessages }

    var body: some View {
        VStack(spacing: 0) {
            if !inline {
                // Header (only in fullscreen mode)
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.text)
                    }

                    HStack(spacing: -6) {
                        ForEach(group.members.prefix(3), id: \.id) { member in
                            AvatarView(name: member.name, size: 28, color: Theme.textMuted,
                                       uid: member.uid, isMe: appState.isMe(member))
                                .environmentObject(appState)
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                        }
                    }

                    Text(group.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)

                    Spacer()

                    Button(action: { showGroupSettings = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 10)

                Rectangle().fill(Theme.separator).frame(height: 0.5)
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(chatMessages.enumerated()), id: \.element.id) { index, msg in
                            VStack(spacing: 0) {
                                if shouldShowTimestamp(at: index) {
                                    Text(groupTimestamp(msg.createdAt))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.textFaint)
                                        .padding(.top, 16)
                                        .padding(.bottom, 8)
                                }
                                groupMessageBubble(msg, index: index).id(msg.id)
                            }
                        }
                        // Sent / Seen indicators
                        if let lastMsg = chatMessages.last, lastMsg.isFromMe {
                            let seen = manager.seenBy(groupId: groupId)
                            if !seen.isEmpty {
                                HStack(spacing: -4) {
                                    Spacer()
                                    ForEach(seen, id: \.userId) { s in
                                        AvatarView(name: s.userName, size: 16, color: Theme.textMuted,
                                                   uid: s.userId, isMe: false)
                                            .environmentObject(appState)
                                            .overlay(Circle().stroke(Theme.bg, lineWidth: 1))
                                    }
                                }
                                .padding(.trailing, 4)
                                .padding(.top, 2)
                            } else {
                                HStack {
                                    Spacer()
                                    Text(L10n.t("sent"))
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textFaint)
                                }
                                .padding(.trailing, 4)
                                .padding(.top, 2)
                            }
                        }

                        if chatMessages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32))
                                    .foregroundColor(Theme.textFaint)
                                Text(L10n.t("no_messages_yet"))
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.top, 60)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: chatMessages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onTapGesture { isTextFocused = false }
            }

            // Input bar
            VStack(spacing: 0) {
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TextField(L10n.t("type_message"), text: $textInput)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.text)
                            .focused($isTextFocused)
                            .submitLabel(.send)
                            .onSubmit { sendText() }
                        if !textInput.isEmpty {
                            Button(action: sendText) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Theme.text)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .liquidGlass(cornerRadius: 20, style: .ultraThin)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .confirmationDialog(L10n.t("delete"), isPresented: Binding(
            get: { messageToDelete != nil },
            set: { if !$0 { messageToDelete = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.t("delete_for_me"), role: .destructive) {
                if let msg = messageToDelete {
                    withAnimation { manager.deleteMessageForMe(msg.id) }
                }
                messageToDelete = nil
            }
            if messageToDelete?.isFromMe == true {
                Button(L10n.t("delete_for_everyone"), role: .destructive) {
                    if let msg = messageToDelete {
                        withAnimation { manager.deleteMessageForEveryone(msg.id) }
                    }
                    messageToDelete = nil
                }
            }
            Button(L10n.t("cancel"), role: .cancel) { messageToDelete = nil }
        }
        .confirmationDialog(L10n.t("report_message"), isPresented: $showReportSheet, titleVisibility: .visible) {
            Button(L10n.t("report_inappropriate"), role: .destructive) {
                if let msgId = reportedMessageId {
                    Log.d("[Report] Message \(msgId) reported as inappropriate")
                }
                reportedMessageId = nil
            }
            Button(L10n.t("report_spam"), role: .destructive) {
                if let msgId = reportedMessageId {
                    Log.d("[Report] Message \(msgId) reported as spam")
                }
                reportedMessageId = nil
            }
            Button(L10n.t("cancel"), role: .cancel) { reportedMessageId = nil }
        }
        .sheet(isPresented: $showGroupSettings) {
            EditGroupView(group: group)
                .environmentObject(appState)
        }
        .sheet(item: $selectedMember) { member in
            FriendDetailView(friend: member)
                .environmentObject(appState)
        }
        .onAppear {
            localMessages = manager.messagesForGroup(groupId)
            manager.loadGroupMessages(groupId)
            manager.markGroupRead(groupId)
            // Poll every 3s as fallback when WS is down
            pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                manager.loadGroupMessages(groupId)
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        .onReceive(WebSocketManager.shared.onChatMessage) { ws in
            if ws.groupId?.lowercased() == groupId.lowercased() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    localMessages = manager.messagesForGroup(groupId)
                    manager.markGroupRead(groupId)
                }
            }
        }
        .onReceive(manager.$messages) { _ in
            let updated = manager.messagesForGroup(groupId)
            if updated != localMessages {
                localMessages = updated
            }
        }
    }

    func sendText() {
        let t = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        manager.sendGroupText(t, groupId: groupId)
        textInput = ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PaktAnalytics.track(.messageSent, properties: ["context": "group"])
    }

    // MARK: - Timestamp logic

    private func shouldShowTimestamp(at index: Int) -> Bool {
        guard index < chatMessages.count else { return false }
        if index == 0 { return true }
        let current = chatMessages[index].createdAt
        let previous = chatMessages[index - 1].createdAt
        return current.timeIntervalSince(previous) > 15 * 60
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"; return f
    }()

    private func groupTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Self.timeFmt.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "\(L10n.t("yesterday")) \(Self.timeFmt.string(from: date))"
        } else {
            return Self.dateFmt.string(from: date)
        }
    }

    // MARK: - Bubble grouping

    private func isFirstInGroup(_ index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = chatMessages[index]
        let prev = chatMessages[index - 1]
        return current.fromId != prev.fromId || current.createdAt.timeIntervalSince(prev.createdAt) > 15 * 60
    }

    private func isLastInGroup(_ index: Int) -> Bool {
        guard index < chatMessages.count - 1 else { return true }
        let current = chatMessages[index]
        let next = chatMessages[index + 1]
        return current.fromId != next.fromId || next.createdAt.timeIntervalSince(current.createdAt) > 15 * 60
    }

    private func openMemberProfile(_ uid: String, name: String) {
        guard uid != myUid else { return }
        let fm = FriendManager.shared
        if let friend = fm.friends.first(where: { $0.id == uid }) {
            selectedMember = friend
        } else {
            // Build a minimal AppUser for non-friends
            selectedMember = AppUser(id: uid, firstName: name, email: "")
        }
    }

    // MARK: - Group message bubble

    func groupMessageBubble(_ msg: ChatMessage, index: Int) -> some View {
        let isMine = msg.fromId == myUid
        let senderName = isMine ? L10n.t("you") : UsernameCache.resolve(uid: msg.fromId, name: msg.fromName)
        let isFirst = isFirstInGroup(index)
        let isLast = isLastInGroup(index)

        return HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 40) }

            if !isMine {
                if isLast {
                    AvatarView(name: senderName, size: 28, color: Theme.textMuted,
                               uid: msg.fromId, isMe: false)
                        .environmentObject(appState)
                        .onTapGesture { openMemberProfile(msg.fromId, name: msg.fromName) }
                } else {
                    Spacer().frame(width: 28)
                }
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 0) {
                if !isMine && isFirst {
                    Text(senderName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.leading, 4)
                        .padding(.bottom, 2)
                        .onTapGesture { openMemberProfile(msg.fromId, name: msg.fromName) }
                }
                EventMessageCard(text: msg.text ?? "", isMine: isMine)
                    .contextMenu {
                        if let text = msg.text {
                            Button {
                                UIPasteboard.general.string = text
                            } label: {
                                Label(L10n.t("copy"), systemImage: "doc.on.doc")
                            }
                        }
                        Button {
                            reportedMessageId = msg.id
                            showReportSheet = true
                        } label: {
                            Label(L10n.t("report"), systemImage: "exclamationmark.triangle")
                        }
                        Button(role: .destructive) {
                            messageToDelete = msg
                        } label: {
                            Label(L10n.t("delete"), systemImage: "trash")
                        }
                    }
            }

            if !isMine { Spacer(minLength: 40) }
        }
        .padding(.vertical, isLast ? 4 : 1)
    }
}
