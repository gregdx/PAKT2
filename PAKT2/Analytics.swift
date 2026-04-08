import Foundation

// MARK: - Analytics Events

enum AnalyticsEvent: String {
    case appOpened = "app_opened"
    case groupCreated = "group_created"
    case groupJoined = "group_joined"
    case messageSent = "message_sent"
    case eventCreated = "event_created"
    case eventGoing = "event_going"
    case friendAdded = "friend_added"
    case onboardingCompleted = "onboarding_completed"
    case tabSwitched = "tab_switched"
    case profileViewed = "profile_viewed"
    case challengeCompleted = "challenge_completed"
}

// MARK: - PaktAnalytics

enum PaktAnalytics {
    // MARK: - Private state

    private static let defaults = UserDefaults.standard
    private static let counterPrefix = "analytics_count_"
    private static let sessionStartKey = "analytics_session_start"
    private static let totalSessionsKey = "analytics_total_sessions"
    private static let userIdKey = "analytics_user_id"

    /// In-memory buffer of recent events (capped at 200)
    private static var _buffer: [(date: Date, event: String, properties: [String: String])] = []
    private static let bufferLimit = 200

    // MARK: - Core tracking

    /// Track an analytics event with optional properties.
    static func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        let name = event.rawValue

        // 1. Log to console
        if properties.isEmpty {
            Log.d("[Analytics] \(name)")
        } else {
            let props = properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            Log.d("[Analytics] \(name) {\(props)}")
        }

        // 2. Increment persistent counter
        let key = counterPrefix + name
        let prev = defaults.integer(forKey: key)
        defaults.set(prev + 1, forKey: key)

        // 3. Append to in-memory buffer
        _buffer.append((date: Date(), event: name, properties: properties))
        if _buffer.count > bufferLimit {
            _buffer.removeFirst(_buffer.count - bufferLimit)
        }
    }

    // MARK: - Session management

    /// Call when the app becomes active / user session starts.
    static func sessionStart() {
        defaults.set(Date().timeIntervalSince1970, forKey: sessionStartKey)
        let total = defaults.integer(forKey: totalSessionsKey)
        defaults.set(total + 1, forKey: totalSessionsKey)
        Log.d("[Analytics] Session #\(total + 1) started")
    }

    /// Call when the app goes to background.
    static func sessionEnd() {
        let start = defaults.double(forKey: sessionStartKey)
        guard start > 0 else { return }
        let duration = Int(Date().timeIntervalSince1970 - start)
        Log.d("[Analytics] Session ended (duration: \(duration)s)")
        defaults.set(0, forKey: sessionStartKey)
    }

    // MARK: - User identification

    /// Associate a user ID with future events.
    static func identify(userId: String) {
        defaults.set(userId, forKey: userIdKey)
        Log.d("[Analytics] Identified user: \(userId.prefix(8))...")
    }

    // MARK: - Convenience readers

    /// Returns the total count for a given event.
    static func count(for event: AnalyticsEvent) -> Int {
        defaults.integer(forKey: counterPrefix + event.rawValue)
    }

    /// Returns the total number of sessions.
    static var totalSessions: Int {
        defaults.integer(forKey: totalSessionsKey)
    }

    /// Returns the in-memory event buffer (most recent events).
    static var recentEvents: [(date: Date, event: String, properties: [String: String])] {
        _buffer
    }

    // MARK: - Legacy stubs (kept for existing call-sites)

    static func signUp()    { track(.onboardingCompleted) }
    static func signOut()   { Log.d("[Analytics] signOut") }
    static func syncScreenTime(minutes: Int) {
        track(.appOpened, properties: ["screentime_minutes": "\(minutes)"])
    }
    static func createGroup(mode: String, scope: String, duration: String) {
        track(.groupCreated, properties: ["mode": mode, "scope": scope, "duration": duration])
    }
    static func joinGroup()          { track(.groupJoined) }
    static func leaveGroup()         { Log.d("[Analytics] leaveGroup") }
    static func sendFriendRequest()  { track(.friendAdded) }
    static func acceptFriendRequest(){ track(.friendAdded, properties: ["action": "accept"]) }
}
