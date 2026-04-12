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
    let startDate: String?
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
        guard let url = URL(string: baseURL + path) else {
            throw APIError(message: "Invalid URL: \(path)", statusCode: 0)
        }
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
                // Refresh failed — force re-login
                await MainActor.run { AppState.shared.signOut() }
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
            Log.d("[API] Decode error: \(error)")
            Log.d("[API] Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
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
        let todayMinutes: Int
        let todaySocialMinutes: Int
        let lastSyncAt: Date?

        // Make the new fields optional so decode doesn't fail if backend is older
        enum CodingKeys: String, CodingKey {
            case userId, username, bio, todayMinutes, todaySocialMinutes, lastSyncAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userId = try c.decode(String.self, forKey: .userId)
            username = try c.decode(String.self, forKey: .username)
            bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
            todayMinutes = try c.decodeIfPresent(Int.self, forKey: .todayMinutes) ?? 0
            todaySocialMinutes = try c.decodeIfPresent(Int.self, forKey: .todaySocialMinutes) ?? 0
            lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        }
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

    func createGroup(name: String, mode: String, scope: String, goalMinutes: Int, duration: String, photoName: String = "", stake: String = "For fun", requiredPlayers: Int = 2, trackedApps: [String] = [], startDate: Date? = nil) async throws -> APIGroup {
        var startDateStr: String? = nil
        if let sd = startDate {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            startDateStr = f.string(from: sd)
        }
        return try await request(.POST, "/groups", body: CreateGroupBody(name: name, mode: mode, scope: scope, goalMinutes: goalMinutes, duration: duration, photoName: photoName, stake: stake, requiredPlayers: requiredPlayers, trackedApps: trackedApps.isEmpty ? nil : trackedApps, startDate: startDateStr))
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

    struct UpdateGroupBody: Encodable {
        let name: String?
        let stake: String?
        let goalMinutes: Int?
        let trackedApps: [String]?
    }

    func updateGroup(_ groupID: String, name: String? = nil, stake: String? = nil, goalMinutes: Int? = nil, trackedApps: [String]? = nil) async throws -> APIGroup {
        let body = UpdateGroupBody(name: name, stake: stake, goalMinutes: goalMinutes, trackedApps: trackedApps)
        return try await request(.PATCH, "/groups/\(groupID)", body: body)
    }

    // MARK: - Scores

    func syncScore(minutes: Int, socialMinutes: Int? = nil, date: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/scores/sync", body: SyncScoreBody(minutes: minutes, socialMinutes: socialMinutes, date: date))
    }

    /// Direct-assign score (bypasses backend GREATEST guard). Use when the
    /// client's DAR-computed value must overwrite a previously-stored inflated
    /// value. Backend broadcasts a `score_corrected` WS event to all co-members.
    func correctScore(minutes: Int, socialMinutes: Int? = nil, date: String) async throws {
        let _: EmptyResponse = try await request(.POST, "/scores/correct", body: SyncScoreBody(minutes: minutes, socialMinutes: socialMinutes, date: date))
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

    struct ServerChatMessage: Decodable {
        let id: String
        let createdAt: Date?
    }

    func sendChatMessage(text: String, toId: String) async throws -> ServerChatMessage {
        struct Body: Encodable { let text: String; let toId: String }
        return try await request(.POST, "/chat", body: Body(text: text, toId: toId))
    }

    func sendActivityProposal(activityTitle: String, activityEmoji: String, toId: String) async throws -> ServerChatMessage {
        struct Body: Encodable { let activityTitle: String; let activityEmoji: String; let toId: String }
        return try await request(.POST, "/chat/activity", body: Body(activityTitle: activityTitle, activityEmoji: activityEmoji, toId: toId))
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

    func sendGroupMessage(groupID: String, text: String) async throws -> ServerChatMessage {
        struct Body: Encodable { let text: String }
        return try await request(.POST, "/groupchat/\(groupID)", body: Body(text: text))
    }

    func markRead(messageId: String, groupId: String? = nil, peerId: String? = nil) async throws {
        struct Body: Encodable { let messageId: String; let groupId: String?; let peerId: String? }
        let _: EmptyResponse = try await request(.POST, "/chat/read", body: Body(messageId: messageId, groupId: groupId, peerId: peerId))
    }

    func getPeerReceipts(peerId: String) async throws -> [ChatReadReceipt] {
        try await request(.GET, "/chat/receipts/\(peerId)")
    }

    func deleteMessage(id: String) async throws {
        let _: EmptyResponse = try await request(.DELETE, "/chat/\(id)")
    }

    // MARK: - Events

    struct AttendRequest: Encodable {
        let eventId: String
        let status: String
        let title: String
        let description: String
        let date: String
        let endDate: String
        let location: String
        let address: String
        let source: String
        let sourceUrl: String
        let imageUrl: String
    }

    func setEventAttendance(_ req: AttendRequest) async throws {
        let _: EmptyResponse = try await request(.POST, "/events/attend", body: req)
    }

    func removeEventAttendance(eventId: String) async throws {
        let _: EmptyResponse = try await request(.DELETE, "/events/\(eventId)/attend")
    }

    struct APIEventAttendee: Decodable {
        let eventId: String
        let userId: String
        let username: String
        let status: String
    }

    func getEventAttendees(eventId: String) async throws -> [APIEventAttendee] {
        try await request(.GET, "/events/\(eventId)/attendees")
    }

    struct APIUserEvent: Decodable, Identifiable {
        let id: String
        let title: String
        let description: String
        let date: Date
        let endDate: Date?
        let location: String
        let address: String
        let source: String
        let sourceUrl: String
        let imageUrl: String
        let status: String

        private enum CodingKeys: String, CodingKey {
            case id, title, description, date, endDate, location, address, source, sourceUrl, imageUrl, status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            description = try container.decode(String.self, forKey: .description)
            date = try container.decode(Date.self, forKey: .date)
            endDate = try? container.decode(Date.self, forKey: .endDate)
            location = try container.decode(String.self, forKey: .location)
            address = try container.decode(String.self, forKey: .address)
            source = try container.decode(String.self, forKey: .source)
            sourceUrl = try container.decode(String.self, forKey: .sourceUrl)
            imageUrl = try container.decode(String.self, forKey: .imageUrl)
            status = try container.decode(String.self, forKey: .status)
        }
    }

    func getUserEvents(userId: String) async throws -> [APIUserEvent] {
        try await request(.GET, "/users/\(userId)/events")
    }

    // MARK: - Cities (Step 1 of events redesign)

    struct APICity: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let countryCode: String
        let lat: Double
        let lng: Double
        let raAreaCode: Int?
        let timezone: String
    }

    func listCities() async throws -> [APICity] {
        try await request(.GET, "/cities")
    }

    func getNearestCity(lat: Double, lng: Double) async throws -> APICity {
        try await request(.GET, "/cities/nearest?lat=\(lat)&lng=\(lng)")
    }

    // MARK: - Events feed (Step 1 read-only)

    struct APIEventListRow: Decodable, Identifiable {
        let id: String
        let title: String
        let description: String
        let date: Date
        let endDate: Date?
        let location: String
        let address: String
        let source: String
        let sourceUrl: String
        let imageUrl: String
        let cityId: String?
        let venueLat: Double?
        let venueLng: Double?
        let visibility: String
        let creatorId: String?
        let myRsvp: String?
        let friendsGoingCount: Int
        let friendNames: [String]
    }

    struct APIEventFriendAttendee: Decodable, Identifiable {
        let userId: String
        let username: String
        let status: String
        var id: String { userId }
    }

    struct APIEventDetail: Decodable, Identifiable {
        let id: String
        let title: String
        let description: String
        let date: Date
        let endDate: Date?
        let location: String
        let address: String
        let source: String
        let sourceUrl: String
        let imageUrl: String
        let cityId: String?
        let venueLat: Double?
        let venueLng: Double?
        let visibility: String
        let creatorId: String?
        let myRsvp: String?
        let friendsGoingCount: Int
        let friendNames: [String]
        let friendAttendees: [APIEventFriendAttendee]
    }

    /// GET /v1/events with filters. Returns events ranked by friends_going_count DESC,
    /// date ASC, enriched with the viewer's RSVP status and friend overlay.
    func listEvents(
        cityId: String,
        filter: String? = nil,
        query: String? = nil,
        source: String? = nil,
        from: Date? = nil,
        to: Date? = nil,
        friendsOnly: Bool = false,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [APIEventListRow] {
        var params: [(String, String)] = [("city_id", cityId)]
        if let filter = filter { params.append(("filter", filter)) }
        if let query = query, !query.isEmpty { params.append(("q", query)) }
        if let source = source { params.append(("source", source)) }
        if friendsOnly { params.append(("friends_only", "1")) }
        params.append(("limit", String(limit)))
        if offset > 0 { params.append(("offset", String(offset))) }

        let iso = ISO8601DateFormatter()
        if let from = from { params.append(("from", iso.string(from: from))) }
        if let to = to { params.append(("to", iso.string(from: to))) }

        let qs = params.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")

        return try await request(.GET, "/events?\(qs)")
    }

    func getEvent(id: String) async throws -> APIEventDetail {
        try await request(.GET, "/events/\(id)")
    }

    // MARK: - Event creation (step 3)

    struct CreateEventBody: Encodable {
        let title: String
        let description: String
        let date: String          // ISO8601
        let endDate: String       // ISO8601 or ""
        let location: String
        let address: String
        let cityId: String
        let venueLat: Double?
        let venueLng: Double?
        let imageUrl: String
        let visibility: String    // "public" | "friends" | "invited"
        let invitedUserIds: [String]

        enum CodingKeys: String, CodingKey {
            case title, description, date
            case endDate = "end_date"
            case location, address
            case cityId = "city_id"
            case venueLat = "venue_lat"
            case venueLng = "venue_lng"
            case imageUrl = "image_url"
            case visibility
            case invitedUserIds = "invited_user_ids"
        }
    }

    func createEvent(_ body: CreateEventBody) async throws -> APIEventDetail {
        try await request(.POST, "/events", body: body)
    }

    func deleteEvent(id: String) async throws {
        let _: EmptyResponse = try await request(.DELETE, "/events/\(id)")
    }

    // MARK: - Chat event sharing

    struct ChatEventBody: Encodable {
        let toId: String
        let eventId: String
        enum CodingKeys: String, CodingKey {
            case toId = "to_id"
            case eventId = "event_id"
        }
    }

    func sendChatEvent(toId: String, eventId: String) async throws {
        let body = ChatEventBody(toId: toId, eventId: eventId)
        let _: EmptyResponse = try await request(.POST, "/chat/event", body: body)
    }

    struct GroupChatEventBody: Encodable {
        let eventId: String
        enum CodingKeys: String, CodingKey {
            case eventId = "event_id"
        }
    }

    func sendGroupChatEvent(groupId: String, eventId: String) async throws {
        let body = GroupChatEventBody(eventId: eventId)
        let _: EmptyResponse = try await request(.POST, "/groupchat/\(groupId)/event", body: body)
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
