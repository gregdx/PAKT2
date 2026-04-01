import Foundation
import Combine

// MARK: - WebSocket Event Types

struct WSScoreUpdate: Decodable {
    let userId: String
    let username: String
    let date: String
    let minutes: Int
    let socialMinutes: Int
}

struct WSGroupUpdate: Decodable {
    let groupId: String
    let type: String  // "member_joined", "member_left", "group_deleted"
    let member: WSMemberInfo?
}

struct WSMemberInfo: Decodable {
    let userId: String
    let username: String?
}

struct WSFriendRequestEvent: Decodable {
    let requestId: String
    let fromId: String
    let fromName: String
}

struct WSFriendEvent: Decodable {
    let friendId: String
    let friendName: String?
}

struct WSInvitationEvent: Decodable {
    let invitationId: String
    let groupId: String?
    let groupName: String?
    let fromName: String?
}

struct WSPendingScore: Decodable {
    let deviceId: String?
    let minutes: Int
    let socialMinutes: Int
    let date: String
}

struct WSChatMessage: Decodable {
    let id: String
    let fromId: String
    let fromName: String?
    let toId: String
    let groupId: String?
    let text: String?
    let activityTitle: String?
    let activityEmoji: String?
    let response: String?
    let createdAt: Date?
}

struct WSChatResponse: Decodable {
    let id: String
    let fromId: String
    let fromName: String?
    let response: String
}

struct WSChatRead: Decodable {
    let userId: String
    let userName: String?
    let groupId: String?
    let peerId: String?
    let messageId: String
}

// MARK: - WebSocketManager

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()

    // Event publishers — views/managers subscribe to these
    let onScoreUpdated = PassthroughSubject<WSScoreUpdate, Never>()
    let onGroupUpdated = PassthroughSubject<WSGroupUpdate, Never>()
    let onFriendRequest = PassthroughSubject<WSFriendRequestEvent, Never>()
    let onFriendAdded = PassthroughSubject<WSFriendEvent, Never>()
    let onFriendRemoved = PassthroughSubject<WSFriendEvent, Never>()
    let onInvitation = PassthroughSubject<WSInvitationEvent, Never>()
    let onPendingScore = PassthroughSubject<WSPendingScore, Never>()
    let onChatMessage = PassthroughSubject<WSChatMessage, Never>()
    let onChatResponse = PassthroughSubject<WSChatResponse, Never>()
    let onChatRead = PassthroughSubject<WSChatRead, Never>()

    @Published var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var subscribedChannels: Set<String> = []
    private var isIntentionalDisconnect = false

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let wsBaseURL = AppConfig.wsBaseURL

    // MARK: - Connect

    private var isConnecting = false
    private var lastConnectAttempt: Date = .distantPast

    func connect() {
        guard let token = AuthManager.shared.accessToken else { return }
        guard !isConnecting else { return }

        // Cooldown: pas plus d'une connexion toutes les 10 secondes
        guard Date().timeIntervalSince(lastConnectAttempt) > 10 else { return }
        lastConnectAttempt = Date()

        isIntentionalDisconnect = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnecting = true

        guard let url = URL(string: "\(wsBaseURL)?token=\(token)") else { isConnecting = false; return }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        // Don't set isConnected=true until we actually receive a message
        reconnectAttempts = 0

        // Re-subscribe to previously subscribed channels
        for channel in subscribedChannels {
            sendAction("subscribe", channel: channel)
        }

        // Start reading messages
        receiveMessage()

        // Start ping timer
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        isIntentionalDisconnect = true
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    // MARK: - Subscribe / Unsubscribe

    func subscribe(_ channel: String) {
        subscribedChannels.insert(channel)
        sendAction("subscribe", channel: channel)
    }

    func unsubscribe(_ channel: String) {
        subscribedChannels.remove(channel)
        sendAction("unsubscribe", channel: channel)
    }

    func unsubscribeAll() {
        for channel in subscribedChannels {
            sendAction("unsubscribe", channel: channel)
        }
        subscribedChannels.removeAll()
    }

    // MARK: - Private

    private func sendAction(_ action: String, channel: String) {
        guard let task = webSocketTask else { return }
        let msg = "{\"action\":\"\(action)\",\"channel\":\"\(channel)\"}"
        task.send(.string(msg)) { _ in }
    }

    private func sendPing() {
        guard let task = webSocketTask else { return }
        task.send(.string("{\"action\":\"ping\"}")) { _ in }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.isConnecting = false
                if !self.isConnected {
                    DispatchQueue.main.async { self.isConnected = true }
                }
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue reading
                self.receiveMessage()

            case .failure:
                self.isConnecting = false
                self.webSocketTask = nil
                DispatchQueue.main.async { self.isConnected = false }
                self.attemptReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        struct WSEnvelope: Decodable {
            let event: String
        }

        guard let envelope = try? decoder.decode(WSEnvelope.self, from: data) else { return }

        struct WSPayload<T: Decodable>: Decodable {
            let event: String
            let data: T
        }

        switch envelope.event {
        case "pong":
            break

        case "score_updated":
            if let payload = try? decoder.decode(WSPayload<WSScoreUpdate>.self, from: data) {
                DispatchQueue.main.async { self.onScoreUpdated.send(payload.data) }
            }

        case "group_updated":
            if let payload = try? decoder.decode(WSPayload<WSGroupUpdate>.self, from: data) {
                DispatchQueue.main.async { self.onGroupUpdated.send(payload.data) }
            }

        case "friend_request":
            if let payload = try? decoder.decode(WSPayload<WSFriendRequestEvent>.self, from: data) {
                DispatchQueue.main.async { self.onFriendRequest.send(payload.data) }
            }

        case "friend_added":
            if let payload = try? decoder.decode(WSPayload<WSFriendEvent>.self, from: data) {
                DispatchQueue.main.async { self.onFriendAdded.send(payload.data) }
            }

        case "friend_removed":
            if let payload = try? decoder.decode(WSPayload<WSFriendEvent>.self, from: data) {
                DispatchQueue.main.async { self.onFriendRemoved.send(payload.data) }
            }

        case "invitation":
            if let payload = try? decoder.decode(WSPayload<WSInvitationEvent>.self, from: data) {
                DispatchQueue.main.async { self.onInvitation.send(payload.data) }
            }

        case "pending_score":
            if let payload = try? decoder.decode(WSPayload<WSPendingScore>.self, from: data) {
                DispatchQueue.main.async { self.onPendingScore.send(payload.data) }
            }

        case "chat_message":
            if let payload = try? decoder.decode(WSPayload<WSChatMessage>.self, from: data) {
                DispatchQueue.main.async { self.onChatMessage.send(payload.data) }
            }

        case "chat_response":
            if let payload = try? decoder.decode(WSPayload<WSChatResponse>.self, from: data) {
                DispatchQueue.main.async { self.onChatResponse.send(payload.data) }
            }

        case "chat_read":
            if let payload = try? decoder.decode(WSPayload<WSChatRead>.self, from: data) {
                DispatchQueue.main.async { self.onChatRead.send(payload.data) }
            }

        default:
            break
        }
    }

    // MARK: - Reconnect

    private func attemptReconnect() {
        guard !isIntentionalDisconnect else { return }
        // Stop trying after 3 attempts — the server may be down
        guard reconnectAttempts < 3 else {
            print("[WS] Max reconnect attempts reached, giving up")
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)

        // Clean up old task before reconnecting
        webSocketTask = nil

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isIntentionalDisconnect else { return }

            // Try refreshing token before reconnecting
            Task {
                _ = await AuthManager.shared.refreshTokens()
                await MainActor.run {
                    self.connect()
                }
            }
        }
    }
}
