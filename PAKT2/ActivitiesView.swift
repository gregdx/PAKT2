import SwiftUI
import Combine

// MARK: - Response enum

enum ProposalResponse: String, Codable, CaseIterable {
    case letsGo       = "lets_go"
    case cantNow      = "cant_now"
    case ratherScroll = "rather_scroll"

    var label: String {
        switch self {
        case .letsGo:       return L10n.t("resp_lets_go")
        case .cantNow:      return L10n.t("resp_cant_now")
        case .ratherScroll: return L10n.t("resp_rather_scroll")
        }
    }
    var color: Color {
        switch self {
        case .letsGo: return Theme.green; case .cantNow: return Theme.orange; case .ratherScroll: return Theme.red
        }
    }
    var icon: String {
        switch self {
        case .letsGo: return "hand.thumbsup.fill"; case .cantNow: return "clock"; case .ratherScroll: return "iphone"
        }
    }
}

// MARK: - Chat message model (text OR activity)

struct ChatMessage: Identifiable, Codable {
    var id: String = UUID().uuidString
    var fromId: String
    var fromName: String
    var toId: String = ""
    var groupId: String? = nil
    var createdAt: Date = Date()

    // Text message
    var text: String? = nil

    // Activity proposal
    var activityTitle: String? = nil
    var activityEmoji: String? = nil
    var response: String? = nil

    var isActivity: Bool { activityTitle != nil }
    var isFromMe: Bool { fromId == (AuthManager.shared.currentUser?.id ?? "") }
    var otherUid: String { isFromMe ? toId : fromId }

    var proposalResponse: ProposalResponse? {
        guard let r = response else { return nil }
        return ProposalResponse(rawValue: r)
    }
}

// MARK: - Manager

final class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published var messages: [ChatMessage] = []
    @Published var readReceipts: [String: [APIClient.ChatReadReceipt]] = [:]  // groupId/peerId → receipts

    private let storageKey = "pakt_chat_messages"
    private var cancellables = Set<AnyCancellable>()
    private var needsSave = false

    var myUid: String { AuthManager.shared.currentUser?.id ?? "" }

    init() {
        loadLocal()
        listenWebSocket()
        // Debounced save — max once per 2 seconds
        $messages
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveLocal() }
            .store(in: &cancellables)
    }

    private func listenWebSocket() {
        WebSocketManager.shared.onChatMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ws in
                guard let self else { return }
                guard !self.messages.contains(where: { $0.id == ws.id }) else { return }
                // Resolve name: WebSocket payload > friends list > existing messages > truncated ID
                let resolvedName = ws.fromName
                    ?? FriendManager.shared.friends.first(where: { $0.id == ws.fromId })?.firstName
                    ?? self.messages.last(where: { $0.fromId == ws.fromId })?.fromName
                    ?? String(ws.fromId.prefix(8))
                let msg = ChatMessage(
                    id: ws.id,
                    fromId: ws.fromId,
                    fromName: resolvedName,
                    toId: ws.toId,
                    groupId: ws.groupId,
                    createdAt: ws.createdAt ?? Date(),
                    text: ws.text,
                    activityTitle: ws.activityTitle,
                    activityEmoji: ws.activityEmoji
                )
                self.messages.append(msg)
            }
            .store(in: &cancellables)

        WebSocketManager.shared.onChatResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ws in
                guard let self else { return }
                if let i = self.messages.firstIndex(where: { $0.id == ws.id }) {
                    self.messages[i].response = ws.response
                }
            }
            .store(in: &cancellables)

        WebSocketManager.shared.onChatRead
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ws in
                guard let self else { return }
                let key = ws.groupId ?? ws.peerId ?? ""
                guard !key.isEmpty else { return }
                let receipt = APIClient.ChatReadReceipt(userId: ws.userId, userName: ws.userName ?? "", lastReadMessageId: ws.messageId)
                var current = self.readReceipts[key] ?? []
                if let i = current.firstIndex(where: { $0.userId == ws.userId }) {
                    current[i] = receipt
                } else {
                    current.append(receipt)
                }
                self.readReceipts[key] = current
            }
            .store(in: &cancellables)
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return }
        messages = decoded
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func conversationUids() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for m in messages.sorted(by: { $0.createdAt > $1.createdAt }) {
            let other = m.otherUid
            if !other.isEmpty && seen.insert(other).inserted { result.append(other) }
        }
        return result
    }

    func messagesWithFriend(_ uid: String) -> [ChatMessage] {
        messages.filter { $0.otherUid == uid }.sorted { $0.createdAt < $1.createdAt }
    }

    func lastMessage(with uid: String) -> ChatMessage? {
        messages.filter { $0.otherUid == uid }.max { $0.createdAt < $1.createdAt }
    }

    func unreadCount(for uid: String) -> Int {
        messages.filter { $0.toId == myUid && $0.fromId == uid && $0.isActivity && $0.response == nil }.count
    }

    func load() {
        Task {
            if let list: [ChatMessage] = try? await APIClient.shared.listActivityProposals() {
                await MainActor.run {
                    // Merge: keep local messages not on server, add server messages not local
                    var merged = self.messages
                    for serverMsg in list {
                        if !merged.contains(where: { $0.id == serverMsg.id }) {
                            merged.append(serverMsg)
                        } else if let i = merged.firstIndex(where: { $0.id == serverMsg.id }) {
                            // Update response from server if local doesn't have it
                            if merged[i].response == nil && serverMsg.response != nil {
                                merged[i].response = serverMsg.response
                            }
                        }
                    }
                    self.messages = merged.sorted { $0.createdAt < $1.createdAt }
                }
            }
        }
    }

    func sendText(_ text: String, toFriendId: String) {
        let msg = ChatMessage(fromId: myUid, fromName: AppState.shared.userName, toId: toFriendId, text: text)
        messages.append(msg)
        // Save immediately for instant feedback
        saveLocal()
        Task {
            try? await APIClient.shared.sendChatMessage(text: text, toId: toFriendId)
        }
    }

    func sendActivity(_ activity: Activity, toFriendId: String) {
        let msg = ChatMessage(
            fromId: myUid, fromName: AppState.shared.userName, toId: toFriendId,
            activityTitle: activity.title, activityEmoji: activity.emoji
        )
        messages.append(msg)
        saveLocal()
        Task {
            try? await APIClient.shared.sendActivityProposal(
                activityTitle: activity.title, activityEmoji: activity.emoji, toId: toFriendId
            )
        }
    }

    func respond(_ msg: ChatMessage, with response: ProposalResponse) {
        if let i = messages.firstIndex(where: { $0.id == msg.id }) {
            messages[i].response = response.rawValue
        }
        Task {
            try? await APIClient.shared.respondToProposal(id: msg.id, response: response.rawValue)
        }
    }

    // MARK: - Group Chat

    func messagesForGroup(_ groupId: String) -> [ChatMessage] {
        messages.filter { $0.groupId == groupId }.sorted { $0.createdAt < $1.createdAt }
    }

    func sendGroupText(_ text: String, groupId: String) {
        let msg = ChatMessage(fromId: myUid, fromName: AppState.shared.userName, groupId: groupId, text: text)
        messages.append(msg)
        saveLocal()
        Task {
            try? await APIClient.shared.sendGroupMessage(groupID: groupId, text: text)
        }
    }

    func loadGroupMessages(_ groupId: String) {
        Task {
            if let response = try? await APIClient.shared.listGroupMessages(groupID: groupId) {
                await MainActor.run {
                    for msg in response.messages {
                        if !self.messages.contains(where: { $0.id == msg.id }) {
                            self.messages.append(msg)
                        }
                    }
                    self.readReceipts[groupId] = response.readReceipts
                }
            }
        }
    }

    func markGroupRead(_ groupId: String) {
        guard let lastMsg = messagesForGroup(groupId).last else { return }
        // Update local immediately
        let receipt = APIClient.ChatReadReceipt(userId: myUid, userName: AppState.shared.userName, lastReadMessageId: lastMsg.id)
        var current = readReceipts[groupId] ?? []
        if let i = current.firstIndex(where: { $0.userId == myUid }) {
            current[i] = receipt
        } else {
            current.append(receipt)
        }
        readReceipts[groupId] = current
        // Sync to backend
        Task { try? await APIClient.shared.markRead(messageId: lastMsg.id, groupId: groupId) }
    }

    func markPeerRead(_ peerId: String) {
        guard let lastMsg = messagesWithFriend(peerId).last else { return }
        let receipt = APIClient.ChatReadReceipt(userId: myUid, userName: AppState.shared.userName, lastReadMessageId: lastMsg.id)
        var current = readReceipts[peerId] ?? []
        if let i = current.firstIndex(where: { $0.userId == myUid }) {
            current[i] = receipt
        } else {
            current.append(receipt)
        }
        readReceipts[peerId] = current
        Task { try? await APIClient.shared.markRead(messageId: lastMsg.id, peerId: peerId) }
    }

    /// Returns user IDs who have seen the last message in a group
    func seenBy(groupId: String) -> [(userId: String, userName: String)] {
        guard let lastMsg = messagesForGroup(groupId).last else { return [] }
        let receipts = readReceipts[groupId] ?? []
        return receipts
            .filter { $0.lastReadMessageId == lastMsg.id && $0.userId != myUid }
            .map { (userId: $0.userId, userName: $0.userName) }
    }

    /// Returns user IDs who have seen the last message in a direct conversation
    func seenByPeer(_ peerId: String) -> Bool {
        guard let lastMsg = messagesWithFriend(peerId).last, lastMsg.isFromMe else { return false }
        let receipts = readReceipts[peerId] ?? []
        return receipts.contains { $0.lastReadMessageId == lastMsg.id && $0.userId == peerId }
    }
}

// MARK: - Picked friend helper

struct PickedFriend: Identifiable, Hashable {
    let id = UUID()
    let uid: String
    let name: String
}

// MARK: - Conversations list

enum MessageTab: String, CaseIterable {
    case groups = "Groups"
    case friends = "Friends"
}

struct ActivitiesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var manager = ActivityManager.shared
    @ObservedObject private var fm = FriendManager.shared
    @State private var showNewConversation = false
    @State private var selectedTab: MessageTab = .groups
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        HStack(alignment: .center) {
                            Text("Messages")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(Theme.text)
                            Spacer()
                            Button(action: { showNewConversation = true }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 17))
                                    .foregroundColor(Theme.textMuted)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(cornerRadius: 10)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 64)
                        .padding(.bottom, 12)

                        // Tab selector
                        HStack(spacing: 0) {
                            ForEach(MessageTab.allCases, id: \.self) { tab in
                                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }) {
                                    VStack(spacing: 8) {
                                        Text(tab.rawValue)
                                            .font(.system(size: 15, weight: selectedTab == tab ? .bold : .medium))
                                            .foregroundColor(selectedTab == tab ? Theme.text : Theme.textMuted)
                                        Rectangle()
                                            .fill(selectedTab == tab ? Theme.text : Color.clear)
                                            .frame(height: 2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)

                        // Content based on tab
                        switch selectedTab {
                        case .groups:
                            groupsList
                        case .friends:
                            friendsList
                        }

                        Spacer().frame(height: 100)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: PickedFriend.self) { friend in
                ConversationView(friendUid: friend.uid, friendName: friend.name, onClose: { navPath.removeLast() })
                    .environmentObject(appState)
                    .navigationBarHidden(true)
            }
            .navigationDestination(for: Group.self) { group in
                GroupChatView(group: group)
                    .environmentObject(appState)
                    .navigationBarHidden(true)
            }
            .sheet(isPresented: $showNewConversation) { friendPickerSheet }
            .onAppear { manager.load() }
        }
    }

    // MARK: - Groups tab

    private var groupsList: some View {
        let sortedGroups = appState.groups.filter { $0.isActive }.sorted { g1, g2 in
            let last1 = manager.messagesForGroup(g1.id.uuidString).last?.createdAt ?? .distantPast
            let last2 = manager.messagesForGroup(g2.id.uuidString).last?.createdAt ?? .distantPast
            return last1 > last2
        }

        return VStack(spacing: 8) {
            if sortedGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("no_challenges"))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 60)
            } else {
                ForEach(sortedGroups) { group in
                    Button(action: { navPath.append(group) }) {
                        groupChatCard(group)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func groupChatCard(_ group: Group) -> some View {
        let lastMsg = manager.messagesForGroup(group.id.uuidString).last

        return HStack(spacing: 14) {
            // Stacked avatars
            ZStack {
                ForEach(Array(group.members.prefix(3).enumerated()), id: \.offset) { i, m in
                    AvatarView(name: m.name, size: 32, color: Theme.textMuted,
                               uid: m.uid, isMe: appState.isMe(m))
                        .environmentObject(appState)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                        .offset(x: CGFloat(i) * 10)
                }
            }
            .frame(width: 48 + CGFloat(min(group.members.count - 1, 2)) * 10, height: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                if let last = lastMsg, let text = last.text {
                    Text("\(last.isFromMe ? "You" : last.fromName): \(text)")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                } else {
                    Text("\(group.members.count) members")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let last = lastMsg {
                    Text(timeAgo(last.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textFaint)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint)
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Friends tab

    private var friendsList: some View {
        let convUids = manager.conversationUids()
        let otherFriends = fm.friends.filter { f in !convUids.contains(f.id) }

        return VStack(spacing: 0) {
            if fm.friends.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("no_friends_yet"))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 60)
            } else {
                // Active conversations (sorted by most recent)
                VStack(spacing: 8) {
                    ForEach(convUids, id: \.self) { uid in
                        conversationCard(uid: uid)
                    }
                }
                .padding(.horizontal, 16)

                // Friends with no conversation yet
                if !otherFriends.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle(text: L10n.t("start_conversation"))
                            .padding(.top, 28)
                            .padding(.bottom, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(otherFriends) { friend in
                                    Button(action: {
                                        navPath.append(PickedFriend(uid: friend.id, name: friend.firstName))
                                    }) {
                                        VStack(spacing: 8) {
                                            AvatarView(name: friend.firstName, size: 52, color: Theme.textMuted,
                                                       uid: friend.id, isMe: false)
                                                .environmentObject(appState)
                                            Text(friend.firstName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(Theme.text)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 68)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Conversation card

    private func conversationCard(uid: String) -> some View {
        let friend = fm.friends.first { $0.id == uid }
        let nameFromMessages = manager.messagesWithFriend(uid).last(where: { $0.fromId == uid })?.fromName
        let name = friend?.firstName ?? nameFromMessages ?? uid.prefix(8).description
        let last = manager.lastMessage(with: uid)
        let unread = manager.unreadCount(for: uid)

        return Button(action: { navPath.append(PickedFriend(uid: uid, name: name)) }) {
            HStack(spacing: 14) {
                AvatarView(name: name, size: 48, color: Theme.textMuted, uid: uid, isMe: false)
                    .environmentObject(appState)

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: unread > 0 ? .bold : .semibold))
                        .foregroundColor(Theme.text)

                    if let last {
                        if let title = last.activityTitle, let emoji = last.activityEmoji {
                            HStack(spacing: 4) {
                                Text(emoji).font(.system(size: 12))
                                Text(title)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textMuted)
                                    .lineLimit(1)
                            }
                        } else if let text = last.text {
                            Text(text)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        }
                    } else {
                        Text(L10n.t("send_first_activity"))
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if let last {
                        Text(timeAgo(last.createdAt))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                    }
                    if unread > 0 {
                        Circle()
                            .fill(Theme.green)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlass(cornerRadius: 16)
        }
    }

    // MARK: - Friend Picker Sheet

    var friendPickerSheet: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { showNewConversation = false }) {
                        Image(systemName: "xmark").font(.system(size: 16)).foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text(L10n.t("start_conversation"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Image(systemName: "xmark").opacity(0).font(.system(size: 16))
                }
                .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(fm.friends) { friend in
                            Button(action: {
                                showNewConversation = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    navPath.append(PickedFriend(uid: friend.id, name: friend.firstName))
                                }
                            }) {
                                HStack(spacing: 14) {
                                    AvatarView(name: friend.firstName, size: 40, color: Theme.textMuted,
                                               uid: friend.id, isMe: false).environmentObject(appState)
                                    Text(friend.firstName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(Theme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 24).padding(.vertical, 12)
                            }
                            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 78)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Time ago helper

    private func timeAgo(_ date: Date) -> String {
        let mins = Int(-date.timeIntervalSinceNow / 60)
        if mins < 1 { return L10n.t("just_now") }
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        let days = hrs / 24
        if days == 1 { return "yesterday" }
        return "\(days)d"
    }
}

// MARK: - Conversation view

struct ConversationView: View {
    let friendUid: String
    let friendName: String
    var isGroupChat: Bool = false
    var onClose: (() -> Void)? = nil

    @EnvironmentObject var appState: AppState
    @ObservedObject private var manager = ActivityManager.shared
    @State private var showActivityPicker = false
    @State private var showFriendProfile = false
    @State private var textInput = ""
    @FocusState private var isTextFocused: Bool

    var chatMessages: [ChatMessage] { manager.messagesWithFriend(friendUid) }
    var myUid: String { manager.myUid }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            conversationHeader

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            // Messages area
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(chatMessages.enumerated()), id: \.element.id) { index, msg in
                            VStack(spacing: 0) {
                                // Timestamp between message groups
                                if shouldShowTimestamp(at: index) {
                                    Text(groupTimestamp(msg.createdAt))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.textFaint)
                                        .padding(.top, 16)
                                        .padding(.bottom, 8)
                                }

                                messageBubble(msg)
                            }
                            .id(msg.id)
                        }

                        if chatMessages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32))
                                    .foregroundColor(Theme.textFaint)
                                Text(L10n.t("send_first_activity"))
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.top, 60)
                        }

                        Spacer().frame(height: 8)
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: chatMessages.count) { _ in
                    if let last = chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onTapGesture { isTextFocused = false }
            }

            // Input bar
            inputBar
        }
        .background(Theme.bg)
        .sheet(isPresented: $showActivityPicker) {
            ActivityPickerSheet(friendUid: friendUid).environmentObject(appState)
        }
        .sheet(isPresented: $showFriendProfile) {
            NavigationView {
                FriendProfileView(user: AppUser(id: friendUid, firstName: friendName, email: ""))
                    .environmentObject(appState)
            }
            .navigationViewStyle(.stack)
        }
    }

    // MARK: - Header

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            Button(action: { onClose?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            Button(action: { showFriendProfile = true }) {
                HStack(spacing: 10) {
                    AvatarView(name: friendName, size: 34, color: Theme.textMuted,
                               uid: friendUid, isMe: false)
                        .environmentObject(appState)
                    Text(friendName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.text)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 10)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
            HStack(spacing: 8) {
                Button(action: { isTextFocused = false; showActivityPicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.green)
                }

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
                                .foregroundColor(Theme.green)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .liquidGlass(cornerRadius: 20)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.bg)
    }

    // MARK: - Send text

    func sendText() {
        let t = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        manager.sendText(t, toFriendId: friendUid)
        textInput = ""
    }

    // MARK: - Timestamp logic

    private func shouldShowTimestamp(at index: Int) -> Bool {
        guard index < chatMessages.count else { return false }
        if index == 0 { return true }
        let current = chatMessages[index].createdAt
        let previous = chatMessages[index - 1].createdAt
        // Show timestamp if more than 15 minutes between messages
        return current.timeIntervalSince(previous) > 15 * 60
    }

    private func groupTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, HH:mm"
            return formatter.string(from: date)
        }
    }

    // MARK: - Message bubble

    func messageBubble(_ msg: ChatMessage) -> some View {
        let isMine = msg.fromId == myUid

        return HStack(alignment: .top, spacing: 8) {
            if isMine { Spacer(minLength: 60) }

            // In group chat, show avatar for other people's messages
            if isGroupChat && !isMine {
                AvatarView(name: msg.fromName, size: 28, color: Theme.textMuted,
                           uid: msg.fromId, isMe: false)
                    .environmentObject(appState)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                // In group chat, show sender name
                if isGroupChat && !isMine {
                    Text(msg.fromName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.leading, 4)
                }

                if msg.isActivity {
                    // Activity proposal card
                    activityProposalCard(msg, isMine: isMine)
                } else {
                    // Text bubble
                    Text(msg.text ?? "")
                        .font(.system(size: 15))
                        .foregroundColor(isMine ? .white : Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isMine ? Theme.green : Theme.bgWarm)
                        .cornerRadius(18)
                }
            }

            if !isMine { Spacer(minLength: 60) }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Activity proposal card

    private func activityProposalCard(_ msg: ChatMessage, isMine: Bool) -> some View {
        let actLabel = (msg.activityTitle ?? "").lowercased()
        let proposal = isMine
            ? L10n.t("proposal_mine").replacingOccurrences(of: "{activity}", with: actLabel)
            : L10n.t("proposal_theirs").replacingOccurrences(of: "{activity}", with: actLabel)

        return VStack(alignment: .leading, spacing: 8) {
            // Emoji + title row
            HStack(spacing: 8) {
                Text(msg.activityEmoji ?? "")
                    .font(.system(size: 22))
                Text(msg.activityTitle ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.text)
            }

            Text(proposal)
                .font(.system(size: 14))
                .foregroundColor(Theme.textMuted)

            // Response badge
            if let resp = msg.proposalResponse {
                HStack(spacing: 4) {
                    Image(systemName: resp.icon).font(.system(size: 13))
                    Text(resp.label).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(resp.color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(resp.color.opacity(0.1))
                .cornerRadius(10)
            }

            // Response buttons (only for received proposals with no response yet)
            if !isMine && msg.response == nil {
                HStack(spacing: 6) {
                    ForEach(ProposalResponse.allCases, id: \.rawValue) { resp in
                        Button(action: {
                            withAnimation { manager.respond(msg, with: resp) }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: resp.icon).font(.system(size: 12))
                                Text(resp.label).font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(resp == .letsGo ? .white : resp.color)
                            .padding(.vertical, 7).padding(.horizontal, 9)
                            .background(resp == .letsGo ? resp.color : resp.color.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(isMine ? Theme.green.opacity(0.08) : Theme.bgWarm)
        .cornerRadius(16)
    }

    // MARK: - Time ago

    func timeAgo(_ date: Date) -> String {
        let mins = Int(-date.timeIntervalSinceNow / 60)
        if mins < 1 { return L10n.t("just_now") }
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        let days = hrs / 24
        if days == 1 { return "yesterday" }
        return "\(days)d"
    }
}

// MARK: - Activity picker (bottom sheet)

struct ActivityPickerSheet: View {
    let friendUid: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var manager = ActivityManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: ActCategory? = nil

    private var categories: [ActCategory] {
        [.outdoor, .sport, .food, .creative, .chill, .social]
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.textFaint)
                    .frame(width: 36, height: 4).padding(.top, 10).padding(.bottom, 14)

                Text(L10n.t("propose_activity"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
                    .tracking(1.2).textCase(.uppercase)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(categories, id: \.rawValue) { cat in
                            let activities = Activity.suggestions.filter { $0.category == cat }

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = selectedCategory == cat ? nil : cat
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: cat.icon).font(.system(size: 13)).foregroundColor(cat.color)
                                        .frame(width: 26, height: 26).background(cat.color.opacity(0.1)).cornerRadius(6)
                                    Text(cat.label.capitalized).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: selectedCategory == cat ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.textFaint)
                                }
                                .padding(.horizontal, 20).padding(.vertical, 12)
                            }

                            if selectedCategory == cat {
                                VStack(spacing: 4) {
                                    ForEach(activities) { activity in
                                        Button(action: {
                                            manager.sendActivity(activity, toFriendId: friendUid)
                                            dismiss()
                                        }) {
                                            HStack(spacing: 10) {
                                                Text(activity.emoji).font(.system(size: 18))
                                                Text(activity.title).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                                                Spacer()
                                                Text(activity.people).font(.system(size: 13)).foregroundColor(Theme.textFaint)
                                            }
                                            .padding(.horizontal, 20).padding(.vertical, 11)
                                            .liquidGlass(cornerRadius: 10)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 8)
                                .transition(.opacity)
                            }

                            if cat != categories.last {
                                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Location Manager

import CoreLocation

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var isAuthorized = false

    override init() {
        super.init()
        manager.delegate = self
        checkStatus()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    private func checkStatus() {
        let status = manager.authorizationStatus
        isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.checkStatus() }
    }
}
