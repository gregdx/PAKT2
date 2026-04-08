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

struct ChatMessage: Identifiable, Codable, Equatable {
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
        let toSave = messages.suffix(500)
        guard let data = try? JSONEncoder().encode(Array(toSave)) else { return }
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



// MARK: - Conversation view

struct ConversationView: View {
    let friendUid: String
    let friendName: String
    var inline: Bool = false
    var onClose: (() -> Void)? = nil

    @EnvironmentObject var appState: AppState
    @ObservedObject private var manager = ActivityManager.shared
    @State private var showActivityPicker = false
    @State private var showFriendProfile = false
    @State private var tappedVenue: Venue? = nil
    @State private var textInput = ""
    @FocusState private var isTextFocused: Bool

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"; return f
    }()
    @State private var messageToDelete: ChatMessage? = nil
    @State private var showReportSheet = false
    @State private var reportedMessageId: String? = nil
    @State private var localMessages: [ChatMessage] = []
    @State private var pollTimer: Timer? = nil

    var chatMessages: [ChatMessage] { localMessages }
    var myUid: String { manager.myUid }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area (full screen, padded top for header)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Space for floating header
                        Spacer().frame(height: inline ? 8 : 70)

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

                        // Space for floating input bar
                        Spacer().frame(height: 80)
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

        }
        .background(Theme.bg)
        .overlay(alignment: .top) { if !inline { conversationHeader } }
        .overlay(alignment: .bottom) { inputBar }
        .sheet(isPresented: $showActivityPicker) {
            ActivityPickerSheet(friendUid: friendUid).environmentObject(appState)
        }
        .sheet(item: $tappedVenue) { venue in
            VenueDetailSheet(venue: venue, userLocation: nil, onInvite: {})
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
            if updated != localMessages {
                localMessages = updated
            }
        }
    }

    // MARK: - Header

    private var conversationHeader: some View {
        Button(action: { showFriendProfile = true }) {
            HStack(spacing: 12) {
                Button(action: { onClose?() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
                AvatarView(name: friendName, size: 34, color: Theme.textMuted,
                           uid: friendUid, isMe: false)
                    .environmentObject(appState)
                Text(friendName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 16)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button(action: { isTextFocused = false; showActivityPicker = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
            }
            TextField(L10n.t("type_message"), text: $textInput)
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
                .focused($isTextFocused)
                .submitLabel(.send)
                .onSubmit { sendText() }
            if !textInput.isEmpty {
                Button(action: sendText) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.text)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 20)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
                        .onTapGesture {
                            if let venue = Venue.all.first(where: { $0.name == msg.activityTitle }) {
                                tappedVenue = venue
                            }
                        }
                        .contextMenu { messageContextMenu(msg) }
                } else {
                    // Text bubble (with event card detection)
                    EventMessageCard(text: msg.text ?? "", isMine: isMine)
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

        Button(role: .destructive) {
            reportedMessageId = msg.id
            showReportSheet = true
        } label: {
            Label(L10n.t("report"), systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: - Activity proposal card

    private func activityProposalCard(_ msg: ChatMessage, isMine: Bool) -> some View {
        let emoji = msg.activityEmoji ?? "🎯"
        let title = msg.activityTitle ?? ""
        let isVenue = emoji == "📍"
        let venue = isVenue ? Venue.all.first(where: { $0.name == title }) : nil

        return VStack(spacing: 0) {
            // Venue photo if it's a spot
            if let venue {
                ZStack {
                    LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: venue.icon).font(.system(size: 30)).foregroundColor(.white.opacity(0.2)))
                    CachedAsyncImage(url: URL(string: venue.photoURL)).scaledToFill()
                }
                .frame(height: 120)
                .clipped()
            }

            // Header — emoji + activity name
            VStack(spacing: 8) {
                if !isVenue {
                    Text(emoji).font(.system(size: 40))
                }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
                if let venue {
                    Text(venue.tagline)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textFaint)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.system(size: 10))
                        Text(venue.address)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.textMuted)
                }
                Text(isMine ? L10n.t("proposal_mine_short") : L10n.t("proposal_theirs_short"))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 14)

            // Response badge (if already responded)
            if let resp = msg.proposalResponse {
                HStack(spacing: 6) {
                    Image(systemName: resp.icon).font(.system(size: 14))
                    Text(resp.label).font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(resp.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(resp.color.opacity(0.08))
            }

            // Response buttons (only for received proposals with no response yet)
            if !isMine && msg.response == nil {
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                    // Let's go — big primary button
                    Button(action: { withAnimation { manager.respond(msg, with: .letsGo) } }) {
                        HStack(spacing: 6) {
                            Text("🤝")
                            Text(L10n.t("resp_lets_go"))
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.text)
                    }

                    Rectangle().fill(Theme.separator).frame(height: 0.5)

                    // Secondary options
                    HStack(spacing: 0) {
                        Button(action: { withAnimation { manager.respond(msg, with: .cantNow) } }) {
                            Text(L10n.t("resp_cant_now"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }

                        Rectangle().fill(Theme.separator).frame(width: 0.5, height: 20)

                        Button(action: { withAnimation { manager.respond(msg, with: .ratherScroll) } }) {
                            HStack(spacing: 4) {
                                Text("📱")
                                    .font(.system(size: 12))
                                Text(L10n.t("resp_rather_scroll"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.textFaint)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .liquidGlass(cornerRadius: 20)
        .frame(maxWidth: 280)
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
    @State private var pickerTab: DiscoverTab = .spots

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

                // Tabs
                HStack(spacing: 8) {
                    ForEach([DiscoverTab.spots, DiscoverTab.free], id: \.self) { tab in
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { pickerTab = tab } }) {
                            Text(tab.label)
                                .font(.system(size: 14, weight: pickerTab == tab ? .semibold : .regular))
                                .foregroundColor(pickerTab == tab ? Theme.bg : Theme.textMuted)
                                .padding(.vertical, 7).padding(.horizontal, 16)
                                .background {
                                    if pickerTab == tab {
                                        RoundedRectangle(cornerRadius: 18).fill(Theme.text)
                                    } else {
                                        RoundedRectangle(cornerRadius: 18).fill(.clear).liquidGlass(cornerRadius: 18)
                                    }
                                }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    if pickerTab == .spots {
                        spotsPickerList
                    } else {
                        freePickerList
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Spots picker

    private var spotsPickerList: some View {
        VStack(spacing: 10) {
            ForEach(Venue.all) { venue in
                Button(action: {
                    let activity = Activity(
                        emoji: "📍", titleEN: venue.name, titleFR: venue.name,
                        subtitleEN: venue.address, subtitleFR: venue.address,
                        category: .outdoor, people: "2"
                    )
                    manager.sendActivity(activity, toFriendId: friendUid)
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        // Mini photo
                        ZStack {
                            LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .overlay(Image(systemName: venue.icon).font(.system(size: 14)).foregroundColor(.white.opacity(0.4)))
                            CachedAsyncImage(url: URL(string: venue.photoURL)).scaledToFill()
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(venue.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Text(venue.tagline)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "paperplane")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 16)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 40)
    }

    // MARK: - Free activities picker

    private var freePickerList: some View {
        VStack(spacing: 8) {
            ForEach(Activity.suggestions) { activity in
                Button(action: {
                    manager.sendActivity(activity, toFriendId: friendUid)
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        Text(activity.emoji).font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(activity.category.color.opacity(0.1))
                            .cornerRadius(12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Text(activity.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "paperplane")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 16)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 40)
    }
}

