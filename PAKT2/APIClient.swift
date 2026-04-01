import Foundation

// MARK: - Request Body Structs

private struct SignUpBody: Encodable {
    let username: String
    let email: String
    let password: String
}

private struct SignInBody: Encodable {
    let email: String
    let password: String
}

private struct AppleBody: Encodable {
    let identityToken: String
    let fullName: String
}

private struct UsernameBody: Encodable {
    let username: String
}

private struct CodeBody: Encodable {
    let code: String
}

private struct RefreshBody: Encodable {
    let refreshToken: String
}

private struct UpdateProfileBody: Encodable {
    var username: String?
    var bio: String?
    var goalHours: Double?
}

private struct PhotoBody: Encodable {
    let photoBase64: String
}

private struct EmailsBody: Encodable {
    let emails: [String]
}

private struct CreateGroupBody: Encodable {
    let name: String
    let mode: String
    let scope: String
    let goalMinutes: Int
    let duration: String
    let photoName: String
    let stake: String
    let requiredPlayers: Int
    let trackedApps: [String]?
}

private struct SyncScoreBody: Encodable {
    let minutes: Int
    let socialMinutes: Int?
    let date: String
}

private struct PendingBody: Encodable {
    let deviceId: String
    let minutes: Int
    let socialMinutes: Int
    let date: String
}

private struct FriendRequestBody: Encodable {
    let toId: String
}

private struct InvitationBody: Encodable {
    let groupId: String
    let toId: String
}

// MARK: - APIClient

class APIClient {
    static let shared = APIClient()

    private var baseURL = AppConfig.apiBaseURL

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // Circuit breaker disabled — was causing cascading failures on tel 2
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            // ISO8601 with fractional seconds (milliseconds)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f1.date(from: str) { return date }
            // ISO8601 without fractional seconds
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let date = f2.date(from: str) { return date }
            // ISO8601 with microseconds (6 digits) — truncate to 3
            if str.contains(".") {
                let parts = str.split(separator: ".")
                if parts.count == 2 {
                    let frac = parts[1].prefix(while: { $0.isNumber })
                    let suffix = parts[1].dropFirst(frac.count)
                    let truncated = "\(parts[0]).\(frac.prefix(3))\(suffix)"
                    if let date = f1.date(from: truncated) { return date }
                }
            }
            // Simple date
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let date = df.date(from: str) { return date }
            // Last resort: return current date instead of crashing
            return Date()
        }
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    /// Token accessor — reads from AuthManager
    var accessToken: String? { AuthManager.shared.accessToken }

    // MARK: - Generic Request

    enum HTTPMethod: String {
        case GET, POST, PUT, PATCH, DELETE
    }

    struct APIError: Error, LocalizedError {
        let message: String
        let statusCode: Int
        var errorDescription: String? { message }
    }

    @discardableResult
    func request<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid response", statusCode: 0)
        }

        // Auto-refresh on 401
        if httpResponse.statusCode == 401 && authenticated {
            let refreshed = await AuthManager.shared.refreshTokens()
            if refreshed {
                if let newToken = AuthManager.shared.accessToken {
                    req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                }
                let (retryData, retryResponse) = try await session.data(for: req)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw APIError(message: "Invalid response", statusCode: 0)
                }
                if retryHTTP.statusCode >= 400 {
                    let errBody = try? JSONDecoder().decode([String: String].self, from: retryData)
                    throw APIError(message: errBody?["error"] ?? "Request failed", statusCode: retryHTTP.statusCode)
                }
                return try decoder.decode(T.self, from: retryData)
            } else {
                throw APIError(message: "Session expired", statusCode: 401)
            }
        }

        if httpResponse.statusCode >= 400 {
            let errBody = try? JSONDecoder().decode([String: String].self, from: data)
            throw APIError(message: errBody?["error"] ?? "Request failed", statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[API] Decode error: \(error)")
            print("[API] Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw error
        }
    }

    // MARK: - Response Types

    struct AuthResponse: Decodable {
        let user: APIUser
        let accessToken: String
        let refreshToken: String
        let extensionToken: String
        let needsVerification: Bool?
        let needsUsername: Bool?
    }

    struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let extensionToken: String
    }

    struct APIUser: Decodable {
        let id: String
        let username: String
        let email: String
        let goalHours: Double
        let bio: String
        let medals: [APIMedal]
        let memberSince: Date
        let isPaused: Bool
        let emailVerified: Bool
    }

    struct APIMedal: Decodable {
        let id: String
        let groupName: String
        let date: Date
        let mode: String
        let avgMinutes: Int
        let goalMinutes: Int
    }

    struct APIUserWrapper: Decodable {
        let user: APIUser
    }

    struct VerifyResponse: Decodable {
        let verified: Bool
    }

    struct PhotoResponse: Decodable {
        let photoBase64: String
    }

    struct APIGroup: Decodable {
        let id: String
        let name: String
        let code: String
        let mode: String
        let scope: String
        let goalMinutes: Int
        let duration: String
        let startDate: Date
        let isFinished: Bool
        let creatorId: String
        let photoName: String
        let isDemo: Bool
        let stake: String
        let requiredPlayers: Int
        let status: String
        let trackedApps: [String]?
        let members: [APIGroupMember]
    }

    struct APIGroupMember: Decodable {
        let userId: String
        let username: String
        let bio: String
    }

    struct APIScore: Decodable {
        let userId: String
        let username: String?
        let date: String
        let minutes: Int
        let socialMinutes: Int
        let dayLabel: String
        let submittedAt: Date
    }

    struct APIFriend: Decodable {
        let userId: String
        let username: String
        let since: Date
    }

    struct APIFriendRequest: Decodable {
        let id: String
        let fromId: String
        let fromName: String
        let toId: String
        let status: String
        let sentAt: Date
    }

    struct APIInvitation: Decodable {
        let id: String
        let groupId: String
        let groupName: String
        let groupMode: String
        let groupGoal: Int
        let fromName: String
        let fromId: String
        let toId: String
        let status: String
        let sentAt: Date
        let groupStake: String?
    }

    // MARK: - Auth

    func signUp(username: String, email: String, password: String) async throws -> AuthResponse {
        try await request(.POST, "/auth/signup", body: SignUpBody(username: username, email: email, password: password), authenticated: false)
    }

    func signIn(email: String, password: String) async throws -> AuthResponse {
        try await request(.POST, "/auth/signin", body: SignInBody(email: email, password: password), authenticated: false)
    }

    func appleSignIn(identityToken: String, fullName: String) async throws -> AuthResponse {
        try await request(.POST, "/auth/apple", body: AppleBody(identityToken: identityToken, fullName: fullName), authenticated: false)
    }

    func appleFinalize(username: String) async throws -> APIUserWrapper {
        try await request(.POST, "/auth/apple/finalize", body: UsernameBody(username: username))
    }

    func verifyEmail(code: String) async throws -> VerifyResponse {
        try await request(.POST, "/auth/verify-email", body: CodeBody(code: code))
    }

    func resendVerification() async throws {
        let _: EmptyResponse = try await request(.POST, "/auth/resend-verification")
    }

    func refreshToken(_ refreshToken: String) async throws -> RefreshResponse {
        try await request(.POST, "/auth/refresh", body: RefreshBody(refreshToken: refreshToken), authenticated: false)
    }

    func deleteAccount() async throws {
        let _: EmptyResponse = try await request(.DELETE, "/auth/account")
    }

    func pauseAccount() async throws {
        let _: EmptyResponse = try await request(.POST, "/auth/pause")
    }

    // MARK: - Users

    func getMe() async throws -> APIUser {
        try await request(.GET, "/me")
    }

    func updateMe(username: String? = nil, bio: String? = nil, goalHours: Double? = nil) async throws -> APIUser {
        try await request(.PATCH, "/me", body: UpdateProfileBody(username: username, bio: bio, goalHours: goalHours))
    }

    func uploadPhoto(base64: String) async throws {
        let _: EmptyResponse = try await request(.PUT, "/me/photo", body: PhotoBody(photoBase64: base64))
    }

    func getPhoto(uid: String) async throws -> PhotoResponse {
        try await request(.GET, "/users/\(uid)/photo")
    }

    func getUserProfile(uid: String) async throws -> UserProfile {
        try await request(.GET, "/users/\(uid)/achievements")
    }

    func searchUsers(query: String) async throws -> [APIUser] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await request(.GET, "/users/search?q=\(encoded)")
    }

    func matchContacts(emails: [String]) async throws -> [APIUser] {
        try await request(.POST, "/users/match-contacts", body: EmailsBody(emails: emails))
    }

    // MARK: - Groups

    func listGroups() async throws -> [APIGroup] {
        try await request(.GET, "/groups")
    }

    func createGroup(name: String, mode: String, scope: String, goalMinutes: Int, duration: String, photoName: String = "", stake: String = "For fun", requiredPlayers: Int = 2, trackedApps: [String] = []) async throws -> APIGroup {
        try await request(.POST, "/groups", body: CreateGroupBody(name: name, mode: mode, scope: scope, goalMinutes: goalMinutes, duration: duration, photoName: photoName, stake: stake, requiredPlayers: requiredPlayers, trackedApps: trackedApps.isEmpty ? nil : trackedApps))
    }

    func getGroupByCode(_ code: String) async throws -> APIGroup {
        try await request(.GET, "/groups/code/\(code)")
    }

    func joinGroup(_ groupID: String) async throws -> APIGroup {
        try await request(.POST, "/groups/\(groupID)/join")
    }

    func leaveGroup(_ groupID: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/groups/\(groupID)/leave")
    }

    func startGroup(_ groupID: String) async throws -> APIGroup {
        try await request(.POST, "/groups/\(groupID)/start")
    }

    func deleteGroup(_ groupID: String) async throws {
        let _: EmptyResponse = try await request(.DELETE, "/groups/\(groupID)")
    }

    // MARK: - Scores

    func syncScore(minutes: Int, socialMinutes: Int? = nil, date: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/scores/sync", body: SyncScoreBody(minutes: minutes, socialMinutes: socialMinutes, date: date))
    }

    func getGroupScores(groupID: String, since: String) async throws -> [APIScore] {
        try await request(.GET, "/scores/group/\(groupID)?since=\(since)")
    }

    func postPending(deviceID: String, minutes: Int, socialMinutes: Int, date: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/scores/pending", body: PendingBody(deviceId: deviceID, minutes: minutes, socialMinutes: socialMinutes, date: date))
    }

    // MARK: - Friends

    func listFriends() async throws -> [APIFriend] {
        try await request(.GET, "/friends")
    }

    func listFriendRequests() async throws -> [APIFriendRequest] {
        try await request(.GET, "/friends/requests")
    }

    func sendFriendRequest(toID: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/friends/request", body: FriendRequestBody(toId: toID))
    }

    func acceptFriendRequest(id: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/friends/request/\(id)/accept")
    }

    func declineFriendRequest(id: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/friends/request/\(id)/decline")
    }

    func removeFriend(uid: String) async throws {
        let _: EmptyResponse = try await request(.DELETE, "/friends/\(uid)")
    }

    // MARK: - Invitations

    func listInvitations() async throws -> [APIInvitation] {
        try await request(.GET, "/invitations")
    }

    func sendInvitation(groupID: String, toID: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/invitations", body: InvitationBody(groupId: groupID, toId: toID))
    }

    func acceptInvitation(id: String) async throws -> APIGroup {
        try await request(.POST, "/invitations/\(id)/accept")
    }

    func declineInvitation(id: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/invitations/\(id)/decline")
    }

    // MARK: - Activities

    func listActivityProposals() async throws -> [ChatMessage] {
        try await request(.GET, "/chat")
    }

    func sendChatMessage(text: String, toId: String) async throws {
        struct Body: Encodable { let text: String; let toId: String }
        let _: EmptyResponse = try await request(.POST, "/chat", body: Body(text: text, toId: toId))
    }

    func sendActivityProposal(activityTitle: String, activityEmoji: String, toId: String) async throws {
        struct Body: Encodable { let activityTitle: String; let activityEmoji: String; let toId: String }
        let _: EmptyResponse = try await request(.POST, "/chat/activity", body: Body(activityTitle: activityTitle, activityEmoji: activityEmoji, toId: toId))
    }

    func respondToProposal(id: String, response: String) async throws {
        struct Body: Encodable { let response: String }
        let _: EmptyResponse = try await request(.POST, "/chat/\(id)/respond", body: Body(response: response))
    }

    // MARK: - Group Chat

    struct GroupChatResponse: Decodable {
        let messages: [ChatMessage]
        let readReceipts: [ChatReadReceipt]
    }

    struct ChatReadReceipt: Decodable {
        let userId: String
        let userName: String
        let lastReadMessageId: String
    }

    func listGroupMessages(groupID: String) async throws -> GroupChatResponse {
        try await request(.GET, "/groupchat/\(groupID)")
    }

    func sendGroupMessage(groupID: String, text: String) async throws {
        struct Body: Encodable { let text: String }
        let _: EmptyResponse = try await request(.POST, "/groupchat/\(groupID)", body: Body(text: text))
    }

    func markRead(messageId: String, groupId: String? = nil, peerId: String? = nil) async throws {
        struct Body: Encodable { let messageId: String; let groupId: String?; let peerId: String? }
        let _: EmptyResponse = try await request(.POST, "/chat/read", body: Body(messageId: messageId, groupId: groupId, peerId: peerId))
    }
}

// MARK: - Helpers

struct EmptyResponse: Decodable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) {
        _encode = { encoder in try wrapped.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
