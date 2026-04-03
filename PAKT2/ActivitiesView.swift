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

    // Handle missing keys from backend (e.g. to_id omitted for group messages)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        fromId = try c.decode(String.self, forKey: .fromId)
        fromName = try c.decodeIfPresent(String.self, forKey: .fromName) ?? ""
        toId = try c.decodeIfPresent(String.self, forKey: .toId) ?? ""
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        text = try c.decodeIfPresent(String.self, forKey: .text)
        activityTitle = try c.decodeIfPresent(String.self, forKey: .activityTitle)
        activityEmoji = try c.decodeIfPresent(String.self, forKey: .activityEmoji)
        response = try c.decodeIfPresent(String.self, forKey: .response)
    }

    // Manual init for creating messages locally
    init(id: String = UUID().uuidString, fromId: String, fromName: String, toId: String = "", groupId: String? = nil, createdAt: Date = Date(), text: String? = nil, activityTitle: String? = nil, activityEmoji: String? = nil, response: String? = nil) {
        self.id = id; self.fromId = fromId; self.fromName = fromName; self.toId = toId
        self.groupId = groupId; self.createdAt = createdAt; self.text = text
        self.activityTitle = activityTitle; self.activityEmoji = activityEmoji; self.response = response
    }
}

// MARK: - Manager

final class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published var messages: [ChatMessage] = []
    @Published var readReceipts: [String: [APIClient.ChatReadReceipt]] = [:]  // groupId/peerId → receipts

    // Local-only state for delete/archive
    @Published var deletedMessageIds: Set<String> = []      // "delete for me"
    @Published var archivedPeerIds: Set<String> = []         // archived conversations
    @Published var deletedPeerIds: Set<String> = []          // deleted conversations

    private let storageKey = "pakt_chat_messages"
    private let deletedMsgKey = "pakt_deleted_msg_ids"
    private let archivedKey = "pakt_archived_peers"
    private let deletedPeersKey = "pakt_deleted_peers"
    private let lastOpenedKey = "pakt_last_opened"
    private var cancellables = Set<AnyCancellable>()
    var lastOpenedAt: [String: Date] = [:]  // peerUid → last time conversation was opened

    var myUid: String { AuthManager.shared.currentUser?.id ?? "" }

    init() {
        loadLocal()
        loadLocalState()
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
                // Skip if we already have this message (by server ID)
                if self.messages.contains(where: { $0.id == ws.id }) {
                    Log.d("[PAKT Chat] WS msg \(ws.id.prefix(8)) already exists, skipping")
                    return
                }

                Log.d("[PAKT Chat] WS msg \(ws.id.prefix(8)) from \(ws.fromId.prefix(8)) — adding to messages")
                let resolvedName = ws.fromName
                    ?? FriendManager.shared.friends.first(where: { $0.id == ws.fromId })?.firstName
                    ?? self.messages.last(where: { $0.fromId == ws.fromId })?.fromName
                    ?? String(ws.fromId.prefix(8))
                let msg = ChatMessage(
                    id: ws.id,
                    fromId: ws.fromId,
                    fromName: resolvedName,
                    toId: ws.toId ?? "",
                    groupId: ws.groupId,
                    createdAt: ws.createdAt ?? Date(),
                    text: ws.text,
                    activityTitle: ws.activityTitle,
                    activityEmoji: ws.activityEmoji
                )
                self.messages.append(msg)
                // Un-delete/un-archive conversation when new message arrives
                let peerUid = msg.isFromMe ? msg.toId : msg.fromId
                if !peerUid.isEmpty && msg.groupId == nil {
                    self.deletedPeerIds.remove(peerUid)
                }
                self.objectWillChange.send()
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
                // For groups: key = groupId. For DMs: key = the userId who read (the friend).
                let key: String
                if let gid = ws.groupId, !gid.isEmpty {
                    key = gid
                } else {
                    key = ws.userId  // The friend who read my message
                }
                guard !key.isEmpty else { return }
                Log.d("[SEEN] WS chat_read: userId=\(ws.userId.prefix(8)) key=\(key.prefix(8)) msgId=\(ws.messageId.prefix(8))")
                let receipt = APIClient.ChatReadReceipt(userId: ws.userId, userName: ws.userName ?? "", lastReadMessageId: ws.messageId)
                var current = self.readReceipts[key] ?? []
                if let i = current.firstIndex(where: { $0.userId == ws.userId }) {
                    current[i] = receipt
                } else {
                    current.append(receipt)
                }
                self.readReceipts[key] = current
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return }
        // Deduplicate: keep only one message per (fromId, toId/groupId, text, createdAt rounded to second)
        var seen = Set<String>()
        var deduped: [ChatMessage] = []
        for msg in decoded {
            let key = "\(msg.fromId)|\(msg.toId)|\(msg.groupId ?? "")|\(msg.text ?? msg.activityTitle ?? "")|\(Int(msg.createdAt.timeIntervalSince1970))"
            if seen.insert(key).inserted {
                deduped.append(msg)
            }
        }
        if deduped.count < decoded.count {
            Log.d("[PAKT Chat] Cleaned \(decoded.count - deduped.count) duplicate messages from local storage")
        }
        messages = deduped
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadLocalState() {
        if let ids = UserDefaults.standard.array(forKey: deletedMsgKey) as? [String] {
            deletedMessageIds = Set(ids)
        }
        if let ids = UserDefaults.standard.array(forKey: archivedKey) as? [String] {
            archivedPeerIds = Set(ids)
        }
        if let ids = UserDefaults.standard.array(forKey: deletedPeersKey) as? [String] {
            deletedPeerIds = Set(ids)
        }
        if let dict = UserDefaults.standard.dictionary(forKey: lastOpenedKey) as? [String: Double] {
            lastOpenedAt = dict.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private func saveLocalState() {
        UserDefaults.standard.set(Array(deletedMessageIds), forKey: deletedMsgKey)
        UserDefaults.standard.set(Array(archivedPeerIds), forKey: archivedKey)
        UserDefaults.standard.set(Array(deletedPeerIds), forKey: deletedPeersKey)
        UserDefaults.standard.set(lastOpenedAt.mapValues { $0.timeIntervalSince1970 }, forKey: lastOpenedKey)
    }

    func markConversationOpened(_ peerUid: String) {
        lastOpenedAt[peerUid] = Date()
        saveLocalState()
        objectWillChange.send()
    }

    func hasUnreadMessages(from peerUid: String) -> Bool {
        let lastOpened = lastOpenedAt[peerUid] ?? .distantPast
        // Check if there's any message FROM the friend AFTER lastOpened
        return messages.contains { msg in
            msg.fromId == peerUid && msg.toId == myUid && msg.groupId == nil
            && !deletedMessageIds.contains(msg.id)
            && msg.createdAt > lastOpened
        }
    }

    // MARK: - Conversations

    func conversationUids() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for m in messages.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard m.groupId == nil else { continue }
            let other = m.otherUid
            if !other.isEmpty && !deletedPeerIds.contains(other) && seen.insert(other).inserted {
                result.append(other)
            }
        }
        return result
    }

    func archivedConversationUids() -> [String] {
        conversationUids().filter { archivedPeerIds.contains($0) }
    }

    func activeConversationUids() -> [String] {
        conversationUids().filter { !archivedPeerIds.contains($0) }
    }

    func messagesWithFriend(_ uid: String) -> [ChatMessage] {
        messages.filter { $0.groupId == nil && $0.otherUid == uid && !deletedMessageIds.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func lastMessage(with uid: String) -> ChatMessage? {
        messagesWithFriend(uid).last
    }

    func unreadCount(for uid: String) -> Int {
        // Only count activity proposals FROM friend with no response yet
        messages.filter {
            $0.toId == myUid && $0.fromId == uid && $0.groupId == nil
            && $0.isActivity && $0.response == nil
            && !deletedMessageIds.contains($0.id)
        }.count
    }

    // MARK: - Send

    func load() {
        Task {
            if let serverList: [ChatMessage] = try? await APIClient.shared.listActivityProposals() {
                await MainActor.run {
                    // Server is the source of truth — replace local with server data
                    // but keep any local-only messages (sent but not yet confirmed)
                    let serverIds = Set(serverList.map { $0.id })
                    // Keep local messages that haven't been synced yet (UUID format, not on server)
                    let localOnly = self.messages.filter { msg in
                        msg.groupId == nil && !serverIds.contains(msg.id)
                        && msg.fromId == self.myUid
                        && msg.createdAt.timeIntervalSinceNow > -30  // sent <30s ago
                    }
                    self.messages = self.messages.filter { $0.groupId != nil }  // keep group messages
                    self.messages.append(contentsOf: serverList)
                    self.messages.append(contentsOf: localOnly)
                    self.messages.sort { $0.createdAt < $1.createdAt }
                    self.objectWillChange.send()
                }
            }
        }
    }

    func sendText(_ text: String, toFriendId: String) {
        let localId = UUID().uuidString
        let msg = ChatMessage(id: localId, fromId: myUid, fromName: AppState.shared.userName, toId: toFriendId, text: text)
        messages.append(msg)
        archivedPeerIds.remove(toFriendId)
        deletedPeerIds.remove(toFriendId)
        saveLocalState()
        saveLocal()
        Task {
            do {
                let server = try await APIClient.shared.sendChatMessage(text: text, toId: toFriendId)
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == localId }) {
                        self.messages[idx].id = server.id
                        if let date = server.createdAt { self.messages[idx].createdAt = date }
                        Log.d("[PAKT Chat] Updated local ID \(localId.prefix(8)) → server ID \(server.id.prefix(8))")
                    }
                }
            } catch {
                Log.d("[PAKT Chat] sendChatMessage failed: \(error)")
            }
        }
    }

    func sendActivity(_ activity: Activity, toFriendId: String) {
        let localId = UUID().uuidString
        let msg = ChatMessage(
            id: localId, fromId: myUid, fromName: AppState.shared.userName, toId: toFriendId,
            activityTitle: activity.title, activityEmoji: activity.emoji
        )
        messages.append(msg)
        archivedPeerIds.remove(toFriendId)
        deletedPeerIds.remove(toFriendId)
        saveLocalState()
        saveLocal()
        Task {
            do {
                let server = try await APIClient.shared.sendActivityProposal(
                    activityTitle: activity.title, activityEmoji: activity.emoji, toId: toFriendId
                )
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == localId }) {
                        self.messages[idx].id = server.id
                        if let date = server.createdAt { self.messages[idx].createdAt = date }
                    }
                }
            } catch {
                Log.d("[PAKT Chat] sendActivity failed: \(error)")
            }
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

    // MARK: - Delete / Archive

    func deleteMessageForMe(_ messageId: String) {
        deletedMessageIds.insert(messageId)
        saveLocalState()
    }

    func deleteMessageForEveryone(_ messageId: String) {
        // Remove from local messages entirely
        messages.removeAll { $0.id == messageId }
        deletedMessageIds.insert(messageId)
        saveLocal()
        saveLocalState()
        // Try to delete on backend (if endpoint exists)
        Task {
            // POST /chat/{id}/delete — may or may not exist on backend
            struct EmptyBody: Encodable {}
            _ = try? await APIClient.shared.deleteMessage(id: messageId)
        }
    }

    func archiveConversation(_ peerUid: String) {
        archivedPeerIds.insert(peerUid)
        saveLocalState()
    }

    func unarchiveConversation(_ peerUid: String) {
        archivedPeerIds.remove(peerUid)
        saveLocalState()
    }

    func deleteConversation(_ peerUid: String) {
        deletedPeerIds.insert(peerUid)
        archivedPeerIds.remove(peerUid)
        saveLocalState()
    }

    // MARK: - Group Chat

    func messagesForGroup(_ groupId: String) -> [ChatMessage] {
        let gid = groupId.lowercased()
        return messages.filter { $0.groupId?.lowercased() == gid && !deletedMessageIds.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func sendGroupText(_ text: String, groupId: String) {
        let localId = UUID().uuidString
        let gid = groupId.lowercased()
        let msg = ChatMessage(id: localId, fromId: myUid, fromName: AppState.shared.userName, groupId: gid, text: text)
        messages.append(msg)
        saveLocal()
        Task {
            do {
                let server = try await APIClient.shared.sendGroupMessage(groupID: groupId, text: text)
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == localId }) {
                        self.messages[idx].id = server.id
                        if let date = server.createdAt { self.messages[idx].createdAt = date }
                    }
                }
            } catch {
                Log.d("[PAKT Chat] sendGroupText failed: \(error)")
            }
        }
    }

    func loadGroupMessages(_ groupId: String) {
        let gid = groupId.lowercased()
        Task {
            if let response = try? await APIClient.shared.listGroupMessages(groupID: groupId) {
                await MainActor.run {
                    let serverIds = Set(response.messages.map { $0.id })
                    let localOnly = self.messages.filter { msg in
                        msg.groupId?.lowercased() == gid && !serverIds.contains(msg.id)
                        && msg.fromId == self.myUid
                        && msg.createdAt.timeIntervalSinceNow > -30
                    }
                    self.messages.removeAll { $0.groupId?.lowercased() == gid }
                    self.messages.append(contentsOf: response.messages)
                    self.messages.append(contentsOf: localOnly)
                    self.messages.sort { $0.createdAt < $1.createdAt }
                    self.readReceipts[gid] = response.readReceipts
                    self.objectWillChange.send()
                }
            }
        }
    }

    func markGroupRead(_ groupId: String) {
        let gid = groupId.lowercased()
        guard let lastMsg = messagesForGroup(groupId).last else { return }
        let receipt = APIClient.ChatReadReceipt(userId: myUid, userName: AppState.shared.userName, lastReadMessageId: lastMsg.id)
        var current = readReceipts[gid] ?? []
        if let i = current.firstIndex(where: { $0.userId == myUid }) {
            current[i] = receipt
        } else {
            current.append(receipt)
        }
        readReceipts[gid] = current
        Task { try? await APIClient.shared.markRead(messageId: lastMsg.id, groupId: groupId) }
    }

    func markPeerRead(_ peerId: String) {
        guard let lastMsg = messagesWithFriend(peerId).last else {
            Log.d("[SEEN] markPeerRead(\(peerId.prefix(8))): no messages")
            return
        }
        Log.d("[SEEN] markPeerRead(\(peerId.prefix(8))): lastMsg.id=\(lastMsg.id.prefix(8)) fromMe=\(lastMsg.isFromMe)")
        let receipt = APIClient.ChatReadReceipt(userId: myUid, userName: AppState.shared.userName, lastReadMessageId: lastMsg.id)
        var current = readReceipts[peerId] ?? []
        if let i = current.firstIndex(where: { $0.userId == myUid }) {
            current[i] = receipt
        } else {
            current.append(receipt)
        }
        readReceipts[peerId] = current
        Task {
            do {
                try await APIClient.shared.markRead(messageId: lastMsg.id, peerId: peerId)
                Log.d("[SEEN] markRead API OK for \(peerId.prefix(8)) msgId=\(lastMsg.id.prefix(8))")
            } catch {
                Log.d("[SEEN] markRead API FAILED: \(error)")
            }
        }
    }

    /// Returns user IDs who have seen the last message in a group
    func seenBy(groupId: String) -> [(userId: String, userName: String)] {
        let gid = groupId.lowercased()
        guard let lastMsg = messagesForGroup(groupId).last else { return [] }
        let receipts = readReceipts[gid] ?? []
        return receipts
            .filter { $0.lastReadMessageId == lastMsg.id && $0.userId != myUid }
            .map { (userId: $0.userId, userName: $0.userName) }
    }

    /// Has the friend seen my last sent message?
    func seenByPeer(_ peerId: String) -> Bool {
        let msgs = messagesWithFriend(peerId)
        guard let lastMsg = msgs.last, lastMsg.isFromMe else { return false }
        let allReceipts = readReceipts[peerId] ?? []
        guard let friendReceipt = allReceipts.first(where: { $0.userId == peerId }) else {
            Log.d("[SEEN] seenByPeer(\(peerId.prefix(8))): no receipt from friend. Keys in readReceipts: \(Array(readReceipts.keys).map { $0.prefix(8) })")
            return false
        }
        Log.d("[SEEN] seenByPeer(\(peerId.prefix(8))): friendReceipt.msgId=\(friendReceipt.lastReadMessageId.prefix(8)) lastMsg.id=\(lastMsg.id.prefix(8)) match=\(friendReceipt.lastReadMessageId == lastMsg.id)")
        if friendReceipt.lastReadMessageId == lastMsg.id { return true }
        let allIds = msgs.map { $0.id }
        if let readIdx = allIds.lastIndex(of: friendReceipt.lastReadMessageId),
           let sentIdx = allIds.lastIndex(of: lastMsg.id) {
            return readIdx >= sentIdx
        }
        return false
    }

    /// Load peer read receipts from server for a specific conversation
    func loadPeerReceipts(_ peerId: String) {
        Task {
            do {
                let list: [APIClient.ChatReadReceipt] = try await APIClient.shared.getPeerReceipts(peerId: peerId)
                await MainActor.run {
                    for r in list {
                        let key = r.userId == self.myUid ? peerId : r.userId
                        var current = self.readReceipts[key] ?? []
                        if let i = current.firstIndex(where: { $0.userId == r.userId }) {
                            current[i] = r
                        } else {
                            current.append(r)
                        }
                        self.readReceipts[key] = current
                    }
                    self.objectWillChange.send()
                    Log.d("[SEEN] Loaded \(list.count) receipts for peer \(peerId.prefix(8))")
                }
            } catch {
                Log.d("[SEEN] loadPeerReceipts FAILED for \(peerId.prefix(8)): \(error)")
            }
        }
    }

    /// Load receipts for all active conversations
    func loadAllPeerReceipts() {
        for uid in activeConversationUids() {
            loadPeerReceipts(uid)
        }
    }

    /// Total unread badge count
    var totalUnread: Int {
        let peerUnread = activeConversationUids().reduce(0) { $0 + unreadCount(for: $1) }
        return peerUnread
    }
}


// MARK: - Chat destination

enum ChatDestination: Identifiable, Hashable {
    case friend(uid: String, name: String)
    case group(id: UUID)

    var id: String {
        switch self {
        case .friend(let uid, _): return "friend_\(uid)"
        case .group(let id): return "group_\(id)"
        }
    }
}

// MARK: - Conversations list

enum MessageTab: CaseIterable {
    case friends, groups

    var label: String {
        switch self {
        case .friends: return L10n.t("friends")
        case .groups:  return L10n.t("groups")
        }
    }
}

struct ActivitiesView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var manager = ActivityManager.shared
    @ObservedObject private var fm = FriendManager.shared
    @State private var activeChat: ChatDestination? = nil
    @State private var showNewConversation = false
    @State private var selectedTab: MessageTab = .friends
    @State private var showArchived = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    if showArchived {
                        archivedSection
                    } else {
                        tabSelector

                        switch selectedTab {
                        case .friends:
                            friendsList
                        case .groups:
                            groupsList
                        }
                    }

                    Spacer().frame(height: 100)
                }
            }
            .refreshable {
                manager.load()
                manager.loadAllPeerReceipts()
                for group in appState.groups where group.isActive {
                    manager.loadGroupMessages(group.id.uuidString)
                }
                clearAllPhotoCaches()
            }
        }
        .sheet(isPresented: $showNewConversation) { friendPickerSheet }
        .fullScreenCover(item: $activeChat) { chat in
            switch chat {
            case .friend(let uid, let name):
                SwipeDismissView {
                    ConversationView(friendUid: uid, friendName: name, onClose: { activeChat = nil })
                        .environmentObject(appState)
                } onDismiss: { activeChat = nil }
            case .group(let gid):
                if let group = appState.groups.first(where: { $0.id == gid }) {
                    SwipeDismissView {
                        GroupChatView(group: group)
                            .environmentObject(appState)
                    } onDismiss: { activeChat = nil }
                }
            }
        }
        .onAppear {
            manager.load()
            manager.loadAllPeerReceipts()
            manager.objectWillChange.send()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            if showArchived {
                Button(action: { withAnimation { showArchived = false } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
            }
            Text(showArchived ? L10n.t("archive") : L10n.t("activities_title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
            HStack(spacing: 8) {
                if !showArchived {
                    let archivedCount = manager.archivedConversationUids().count
                    if archivedCount > 0 {
                        Button(action: { withAnimation { showArchived = true } }) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 15))
                                .foregroundColor(Theme.textMuted)
                                .frame(width: 36, height: 36)
                                .liquidGlass(cornerRadius: 10)
                        }
                    }
                }
                Button(action: { showNewConversation = true }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 36, height: 36)
                        .liquidGlass(cornerRadius: 10)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - Tab selector (moved above search)

    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(MessageTab.allCases, id: \.self) { tab in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }) {
                    Text(tab.label)
                        .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? Theme.bg : Theme.textMuted)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(selectedTab == tab ? Theme.text : Color.clear)
                        .cornerRadius(20)
                        .liquidGlass(cornerRadius: selectedTab == tab ? 0 : 20)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Friends tab

    private var friendsList: some View {
        let convUids = manager.activeConversationUids()
        let otherFriends = fm.friends.filter { f in
            !manager.conversationUids().contains(f.id)
        }

        return VStack(spacing: 0) {
            if fm.friends.isEmpty && convUids.isEmpty {
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
                VStack(spacing: 10) {
                    ForEach(convUids, id: \.self) { uid in
                        conversationCard(uid: uid)
                    }
                }
                .padding(.horizontal, 20)

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
                                        activeChat = .friend(uid: friend.id, name: friend.firstName)
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

    // MARK: - Archived section

    private var archivedSection: some View {
        let uids = manager.archivedConversationUids()
        return VStack(spacing: 0) {
            if uids.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("no_archived_conversations"))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 60)
            } else {
                ForEach(uids, id: \.self) { uid in
                    conversationCard(uid: uid, isArchived: true)
                }
            }
        }
    }

    // MARK: - Groups tab

    private var groupsList: some View {
        let sortedGroups = appState.groups.filter { $0.isActive }.sorted { g1, g2 in
            let last1 = manager.messagesForGroup(g1.id.uuidString).last?.createdAt ?? .distantPast
            let last2 = manager.messagesForGroup(g2.id.uuidString).last?.createdAt ?? .distantPast
            return last1 > last2
        }

        return VStack(spacing: 0) {
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
                VStack(spacing: 10) {
                    ForEach(sortedGroups) { group in
                        Button(action: { activeChat = .group(id: group.id) }) {
                            groupChatCard(group)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func groupChatCard(_ group: Group) -> some View {
        let lastMsg = manager.messagesForGroup(group.id.uuidString).last

        return HStack(spacing: 14) {
            // Stacked member avatars
            ZStack {
                ForEach(Array(group.members.prefix(3).enumerated()), id: \.offset) { i, member in
                    AvatarView(name: member.name, size: 36, color: Theme.textMuted,
                               uid: member.uid, isMe: appState.isMe(member))
                        .environmentObject(appState)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                        .offset(x: CGFloat(i) * 10)
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(group.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.text)
                    Spacer()
                    if let last = lastMsg {
                        Text(timeAgo(last.createdAt))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                    }
                }

                HStack(spacing: 4) {
                    if let last = lastMsg, let text = last.text {
                        Text(last.isFromMe ? "\(L10n.t("you")): \(text)" : "\(last.fromName): \(text)")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    } else {
                        Text("\(group.members.count) \(L10n.t("members_count"))")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textFaint)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Conversation card with swipe actions

    private func conversationCard(uid: String, isArchived: Bool = false) -> some View {
        let friend = fm.friends.first { $0.id == uid }
        let nameFromMessages = manager.messagesWithFriend(uid).last(where: { $0.fromId == uid })?.fromName
        let name = friend?.firstName ?? nameFromMessages ?? uid.prefix(8).description
        let last = manager.lastMessage(with: uid)
        let hasUnread = manager.hasUnreadMessages(from: uid)
        let seen = manager.seenByPeer(uid)

        return Button(action: { activeChat = .friend(uid: uid, name: name) }) {
            HStack(spacing: 14) {
                AvatarView(name: name, size: 52, color: Theme.textMuted, uid: uid, isMe: false)
                    .environmentObject(appState)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name)
                            .font(.system(size: 16, weight: hasUnread ? .bold : .regular))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if let last {
                            Text(timeAgo(last.createdAt))
                                .font(.system(size: 12))
                                .foregroundColor(hasUnread ? Theme.green : Theme.textFaint)
                        }
                    }

                    HStack(spacing: 4) {
                        if let last {
                            if let title = last.activityTitle, let emoji = last.activityEmoji {
                                HStack(spacing: 4) {
                                    if last.isFromMe { Text("\(L10n.t("you")):").font(.system(size: 14)).foregroundColor(Theme.textMuted) }
                                    Text(emoji).font(.system(size: 12))
                                    Text(title)
                                        .font(.system(size: 14, weight: hasUnread ? .medium : .regular))
                                        .foregroundColor(hasUnread ? Theme.text : Theme.textMuted)
                                        .lineLimit(1)
                                }
                            } else if let text = last.text {
                                Text(last.isFromMe ? "\(L10n.t("you")): \(text)" : text)
                                    .font(.system(size: 14, weight: hasUnread ? .medium : .regular))
                                    .foregroundColor(hasUnread ? Theme.text : Theme.textMuted)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(L10n.t("send_first_activity"))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textFaint)
                        }

                        Spacer()

                        // Unread dot or seen avatar
                        if hasUnread {
                            Circle()
                                .fill(Theme.green)
                                .frame(width: 10, height: 10)
                        } else if let last, last.isFromMe && seen {
                            AvatarView(name: name, size: 16, color: Theme.textMuted, uid: uid, isMe: false)
                                .environmentObject(appState)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .liquidGlass(cornerRadius: 16)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if isArchived {
                Button {
                    withAnimation { manager.unarchiveConversation(uid) }
                } label: {
                    Label(L10n.t("unarchive"), systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    withAnimation { manager.archiveConversation(uid) }
                } label: {
                    Label(L10n.t("archive"), systemImage: "archivebox")
                }
            }
            Button(role: .destructive) {
                withAnimation { manager.deleteConversation(uid) }
            } label: {
                Label(L10n.t("delete"), systemImage: "trash")
            }
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
                                    activeChat = .friend(uid: friend.id, name: friend.firstName)
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

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"; return f
    }()
    @State private var messageToDelete: ChatMessage? = nil
    @State private var localMessages: [ChatMessage] = []
    @State private var pollTimer: Timer? = nil

    var chatMessages: [ChatMessage] { localMessages }
    var myUid: String { manager.myUid }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            conversationHeader

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            // Messages area
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
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

                                messageBubble(msg, index: index)
                            }
                            .id(msg.id)
                        }

                        // Sent / Seen indicator
                        if let lastMsg = chatMessages.last, lastMsg.isFromMe {
                            if manager.seenByPeer(friendUid) {
                                HStack(spacing: 4) {
                                    Spacer()
                                    AvatarView(name: friendName, size: 16, color: Theme.textMuted,
                                               uid: friendUid, isMe: false)
                                        .environmentObject(appState)
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
                                Text(L10n.t("send_first_activity"))
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.top, 60)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                }
                .onAppear {
                    // Scroll to bottom when opening conversation
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
        .onAppear {
            localMessages = manager.messagesWithFriend(friendUid)
            manager.markConversationOpened(friendUid)
            manager.markPeerRead(friendUid)
            manager.loadPeerReceipts(friendUid)
            // Poll every 3s as fallback when WS is down
            pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                manager.load()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let updated = manager.messagesWithFriend(friendUid)
                    if updated.count != localMessages.count {
                        localMessages = updated
                        manager.markPeerRead(friendUid)
                        manager.markConversationOpened(friendUid)
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        .onReceive(WebSocketManager.shared.onChatMessage) { ws in
            if ws.groupId == nil && (ws.fromId == friendUid || ws.toId == friendUid) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    localMessages = manager.messagesWithFriend(friendUid)
                    manager.markPeerRead(friendUid)
                    manager.markConversationOpened(friendUid)
                }
            }
        }
        .onReceive(manager.$messages) { _ in
            let updated = manager.messagesWithFriend(friendUid)
            if updated.count != localMessages.count {
                localMessages = updated
            }
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(friendName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.text)
                    }
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
            return Self.timeFmt.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "\(L10n.t("yesterday")) \(Self.timeFmt.string(from: date))"
        } else {
            return Self.dateTimeFmt.string(from: date)
        }
    }

    // MARK: - Messenger-style bubble grouping

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

    // MARK: - Message bubble

    func messageBubble(_ msg: ChatMessage, index: Int) -> some View {
        let isMine = msg.fromId == myUid
        let isFirst = isFirstInGroup(index)
        let isLast = isLastInGroup(index)

        return HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 60) }

            // Avatar: only show on last message of a group from other person
            if !isMine {
                if isLast {
                    AvatarView(name: msg.fromName, size: 28, color: Theme.textMuted,
                               uid: msg.fromId, isMe: false)
                        .environmentObject(appState)
                } else {
                    Spacer().frame(width: 28)
                }
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 0) {
                if msg.isActivity {
                    activityProposalCard(msg, isMine: isMine)
                        .contextMenu { messageContextMenu(msg) }
                } else {
                    // Text bubble with Messenger-style corners
                    Text(msg.text ?? "")
                        .font(.system(size: 15))
                        .foregroundColor(isMine ? .white : Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isMine ? Theme.green : Theme.bgWarm)
                        .clipShape(BubbleShape(
                            isMine: isMine,
                            isFirst: isFirst,
                            isLast: isLast
                        ))
                        .contextMenu { messageContextMenu(msg) }
                }
            }

            if !isMine { Spacer(minLength: 60) }
        }
        .padding(.vertical, isLast ? 4 : 1)
    }

    // MARK: - Context menu (long press)

    @ViewBuilder
    private func messageContextMenu(_ msg: ChatMessage) -> some View {
        if let text = msg.text {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label(L10n.t("copy"), systemImage: "doc.on.doc")
            }
        }

        Button(role: .destructive) {
            messageToDelete = msg
        } label: {
            Label(L10n.t("delete"), systemImage: "trash")
        }
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

}

// MARK: - Messenger-style bubble shape

struct BubbleShape: Shape {
    let isMine: Bool
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = 6  // smaller corner for tail side

        // Determine corner radii
        let topLeft: CGFloat = isMine ? r : (isFirst ? r : tail)
        let topRight: CGFloat = isMine ? (isFirst ? r : tail) : r
        let bottomLeft: CGFloat = isMine ? r : (isLast ? tail : tail)
        let bottomRight: CGFloat = isMine ? (isLast ? tail : tail) : r

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                        radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
            path.addArc(center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                        radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                        radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
            path.addArc(center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                        radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
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
