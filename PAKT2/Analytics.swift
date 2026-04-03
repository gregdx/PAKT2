import Foundation

// TODO: Integrate analytics provider (Mixpanel, PostHog, etc.)
enum PaktAnalytics {
    static func signUp() {}
    static func signOut() {}
    static func syncScreenTime(minutes: Int) {}
    static func createGroup(mode: String, scope: String, duration: String) {}
    static func joinGroup() {}
    static func leaveGroup() {}
    static func sendFriendRequest() {}
    static func acceptFriendRequest() {}
}
