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
    var toId: String
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

    private let storageKey = "pakt_chat_messages"
    private var cancellables = Set<AnyCancellable>()
    private var needsSave = false

    var myUid: String { AuthManager.shared.currentUser?.id ?? "" }

    init() {
        loadLocal()
        purgeExpired()
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
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return }
        messages = decoded
    }

    /// Supprime les messages de plus de 24h
    private func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        messages.removeAll { $0.createdAt < cutoff }
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
}

// MARK: - Conversations list

struct PickedFriend: Identifiable {
    let id = UUID()
    let uid: String
    let name: String
}

struct ActivitiesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var manager = ActivityManager.shared
    @ObservedObject private var fm = FriendManager.shared
    @State private var pickedFriend: PickedFriend? = nil
    @State private var showNewConversation = false
    @State private var selectedActivityTab = 0
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationView {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text(L10n.t("activities_title"))
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(Theme.text)
                            Spacer()
                            if selectedActivityTab == 0 {
                                Button(action: { showNewConversation = true }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 17))
                                        .foregroundColor(Theme.textMuted)
                                        .frame(width: 40, height: 40)
                                        .liquidGlass(cornerRadius: 10)
                                }
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 16)

                        // Tab picker
                        HStack(spacing: 0) {
                            activityTabButton(L10n.t("tab_friends"), index: 0)
                            activityTabButton(L10n.t("tab_near_you"), index: 1)
                        }
                        .padding(3)
                        .liquidGlass(cornerRadius: 12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                        if selectedActivityTab == 0 {
                            friendsContent
                        } else {
                            nearYouContent
                        }

                        Spacer().frame(height: 100)
                    }
                }

            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewConversation) { friendPickerSheet }
            .fullScreenCover(item: $pickedFriend) { friend in
                ConversationView(friendUid: friend.uid, friendName: friend.name, onClose: { pickedFriend = nil })
                    .environmentObject(appState)
            }
            .onAppear { manager.load() }
        }
        .navigationViewStyle(.stack)
    }

    func conversationRow(uid: String) -> some View {
        let friend = fm.friends.first { $0.id == uid }
        // Fallback: check message history for the name if friend not in list
        let nameFromMessages = manager.messagesWithFriend(uid).last(where: { $0.fromId == uid })?.fromName
        let name = friend?.firstName ?? nameFromMessages ?? uid.prefix(8).description
        let last = manager.lastMessage(with: uid)
        let unread = manager.unreadCount(for: uid)

        return Button(action: { pickedFriend = PickedFriend(uid: uid, name: name) }) {
            HStack(spacing: 14) {
                AvatarView(name: name, size: 44, color: Theme.textMuted, uid: uid, isMe: false)
                    .environmentObject(appState)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 16, weight: unread > 0 ? .bold : .semibold))
                        .foregroundColor(Theme.text)
                    if let last {
                        if let title = last.activityTitle, let emoji = last.activityEmoji {
                            HStack(spacing: 4) {
                                Text(emoji).font(.system(size: 12))
                                Text(title).font(.system(size: 13)).foregroundColor(Theme.textMuted).lineLimit(1)
                            }
                        } else if let text = last.text {
                            Text(text).font(.system(size: 13)).foregroundColor(Theme.textMuted).lineLimit(1)
                        }
                    } else {
                        Text(L10n.t("send_first_activity")).font(.system(size: 12)).foregroundColor(Theme.textFaint)
                    }
                }
                Spacer()
                if unread > 0 { Circle().fill(Theme.green).frame(width: 10, height: 10) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    // MARK: - Tab Button

    private func activityTabButton(_ label: String, index: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedActivityTab = index } }) {
            Text(label)
                .font(.system(size: 15, weight: selectedActivityTab == index ? .bold : .regular))
                .foregroundColor(selectedActivityTab == index ? Theme.text : Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedActivityTab == index ? Theme.bgCard : Color.clear)
                .cornerRadius(10)
        }
    }

    // MARK: - Friends Content

    private var friendsContent: some View {
        let convUids = manager.conversationUids()
        let otherFriends = fm.friends.filter { f in !convUids.contains(f.id) }

        return SwiftUI.Group {
            if fm.friends.isEmpty {
                VStack(spacing: 12) {
                    Text(L10n.t("no_friends_yet"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .padding(.top, 60)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(convUids, id: \.self) { uid in conversationRow(uid: uid) }
                    if !otherFriends.isEmpty && !convUids.isEmpty {
                        SectionTitle(text: L10n.t("start_conversation")).padding(.top, 20)
                    }
                    ForEach(otherFriends) { friend in conversationRow(uid: friend.id) }
                }
            }
        }
    }

    // MARK: - Near You Content

    private var nearYouContent: some View {
        VStack(spacing: 0) {
            if !locationManager.isAuthorized {
                // Location permission
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)
                    Image(systemName: "location.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("location_needed"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Button(action: { locationManager.requestPermission() }) {
                        Text(L10n.t("allow_location"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .liquidGlass(cornerRadius: 14)
                    }
                    .padding(.horizontal, 24)
                }
            } else {
                // Coming soon — placeholder for local partnerships
                VStack(spacing: 20) {
                    Spacer().frame(height: 60)

                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 44))
                        .foregroundColor(Theme.textFaint)

                    Text(L10n.t("near_you_coming"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.text)

                    // Preview cards — fake local spots
                    VStack(spacing: 12) {
                        nearYouPlaceholderCard(emoji: "☕", name: "Café de Flore", type: "Coffee shop")
                        nearYouPlaceholderCard(emoji: "🧗", name: "Climb Up", type: "Climbing gym")
                        nearYouPlaceholderCard(emoji: "🌳", name: "Central Park", type: "Park")
                    }
                    .padding(.horizontal, 24)
                    .opacity(0.4)
                }
            }
        }
    }

    private func nearYouPlaceholderCard(emoji: String, name: String, type: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.bgWarm)
                    .frame(width: 56, height: 56)
                Text(emoji)
                    .font(.system(size: 26))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(type)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Theme.textFaint)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Friend Picker

    var friendPickerSheet: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { showNewConversation = false }) {
                        Image(systemName: "xmark").font(.system(size: 16)).foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text(L10n.t("start_conversation")).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.textMuted)
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
                                    pickedFriend = PickedFriend(uid: friend.id, name: friend.firstName)
                                }
                            }) {
                                HStack(spacing: 14) {
                                    AvatarView(name: friend.firstName, size: 40, color: Theme.textMuted,
                                               uid: friend.id, isMe: false).environmentObject(appState)
                                    Text(friend.firstName).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
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
}

// MARK: - Conversation view

struct ConversationView: View {
    let friendUid: String
    let friendName: String
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
            // Header with back button + tappable friend info
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
            .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 10)

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            // Messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        // Expiration notice
                        Text(L10n.t("chat_expires"))
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                            .padding(.top, 12).padding(.bottom, 4)

                        ForEach(chatMessages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        if chatMessages.isEmpty {
                            Text(L10n.t("send_first_activity"))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textMuted)
                                .padding(.top, 40)
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

    func sendText() {
        let t = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        manager.sendText(t, toFriendId: friendUid)
        textInput = ""
    }

    // MARK: - Message bubble

    func messageBubble(_ msg: ChatMessage) -> some View {
        let isMine = msg.fromId == myUid

        return HStack {
            if isMine { Spacer(minLength: 60) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if msg.isActivity {
                    // Activity card
                    let actLabel = (msg.activityTitle ?? "").lowercased()
                    let proposal = isMine
                        ? L10n.t("proposal_mine").replacingOccurrences(of: "{activity}", with: actLabel)
                        : L10n.t("proposal_theirs").replacingOccurrences(of: "{activity}", with: actLabel)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(proposal)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                        HStack(spacing: 6) {
                            Text(msg.activityEmoji ?? "").font(.system(size: 14))
                            Text(msg.activityTitle ?? "")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                            Spacer()
                            Text(timeAgo(msg.createdAt))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textFaint)
                        }
                    }
                    .padding(12)
                    .background(isMine ? Theme.green.opacity(0.1) : Theme.bgWarm)
                    .cornerRadius(16)

                    // Response
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

                    // Response buttons
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
                } else {
                    // Text message
                    Text(msg.text ?? "")
                        .font(.system(size: 15))
                        .foregroundColor(isMine ? .white : Theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(isMine ? Theme.green : Theme.bgWarm)
                        .cornerRadius(18)
                }
            }

            if !isMine { Spacer(minLength: 60) }
        }
    }

    func timeAgo(_ date: Date) -> String {
        let mins = Int(-date.timeIntervalSinceNow / 60)
        if mins < 1 { return L10n.t("just_now") }
        if mins < 60 { return "\(mins)min" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }
}

// MARK: - Friend profile sheet

struct FriendProfileSheet: View {
    let friendUid: String
    let friendName: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fm = FriendManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var profile: UserProfile? = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.textFaint)
                    .frame(width: 36, height: 4).padding(.top, 10)

                AvatarView(name: friendName, size: 72, color: Theme.textMuted,
                           uid: friendUid, isMe: false)
                    .environmentObject(appState)

                Text(friendName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)

                if let p = profile {
                    VStack(spacing: 12) {
                        if !p.bio.isEmpty {
                            Text(p.bio)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        HStack(spacing: 24) {
                            profileStat(value: "\(p.achievements.count)", label: L10n.t("medals"))
                        }
                        let df = DateFormatter()
                        let _ = df.dateFormat = "MMM yyyy"
                        Text("\(L10n.t("member_since")) \(df.string(from: p.memberSince))")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                    }
                }

                Spacer()

                Button(action: {
                    fm.removeFriend(friendUid)
                    dismiss()
                }) {
                    Text(L10n.t("remove"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.red)
                }
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium])
        .task {
            profile = try? await APIClient.shared.getUserProfile(uid: friendUid)
        }
    }

    func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            Text(label).font(.system(size: 13)).foregroundColor(Theme.textFaint)
        }
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
