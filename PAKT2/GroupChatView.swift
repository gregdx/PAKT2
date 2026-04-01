import SwiftUI

struct GroupChatView: View {
    let group: Group
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = ActivityManager.shared
    @State private var textInput = ""
    @FocusState private var isTextFocused: Bool
    @GestureState private var dragOffset: CGFloat = 0

    var groupId: String { group.id.uuidString }
    var myUid: String { manager.myUid }
    var chatMessages: [ChatMessage] { manager.messagesForGroup(groupId) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                }

                // Group member avatars
                HStack(spacing: -6) {
                    ForEach(group.members.prefix(4), id: \.id) { member in
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

                Text("\(group.members.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textFaint)
                Image(systemName: "person.2")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 10)

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            // Messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(chatMessages) { msg in
                            groupMessageBubble(msg).id(msg.id)
                        }
                        // Read receipts — small avatars of people who have seen the last message
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
                            .padding(.trailing, 16)
                            .padding(.top, -4)
                        }

                        if chatMessages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32))
                                    .foregroundColor(Theme.textFaint)
                                Text("No messages yet")
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.top, 60)
                        }
                        Spacer().frame(height: 8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onChange(of: chatMessages.count) { _ in
                    if let last = chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onTapGesture { isTextFocused = false }
            }

            // Input bar
            VStack(spacing: 0) {
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("Message...", text: $textInput)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.text)
                            .focused($isTextFocused)
                            .submitLabel(.send)
                            .onSubmit { sendText() }
                        if !textInput.isEmpty {
                            Button(action: sendText) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Theme.green)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .liquidGlass(cornerRadius: 20)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .onAppear {
            manager.loadGroupMessages(groupId)
            manager.markGroupRead(groupId)
        }
        .onChange(of: chatMessages.count) { _ in
            manager.markGroupRead(groupId)
        }
    }

    func sendText() {
        let t = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        manager.sendGroupText(t, groupId: groupId)
        textInput = ""
    }

    // MARK: - Group message bubble

    func groupMessageBubble(_ msg: ChatMessage) -> some View {
        let isMine = msg.fromId == myUid
        let senderName = isMine ? "You" : UsernameCache.resolve(uid: msg.fromId, name: msg.fromName)

        return HStack(alignment: .top, spacing: 8) {
            if isMine { Spacer(minLength: 40) }

            if !isMine {
                AvatarView(name: senderName, size: 28, color: Theme.textMuted,
                           uid: msg.fromId, isMe: false)
                    .environmentObject(appState)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if !isMine {
                    Text(senderName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                }
                Text(msg.text ?? "")
                    .font(.system(size: 15))
                    .foregroundColor(isMine ? .white : Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(isMine ? Theme.green : Theme.bgWarm)
                    .cornerRadius(18)
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }
}
