import Foundation
import SwiftUI

// MARK: - PreferenceKeys
struct TodayMinutesKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        let next = nextValue()
        if next > value { value = next }
    }
}

struct SocialMinutesKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        let next = nextValue()
        if next > value { value = next }
    }
}

struct WeekAvgKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        let next = nextValue()
        if next > value { value = next }
    }
}

struct MonthAvgKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        let next = nextValue()
        if next > value { value = next }
    }
}

/// Carries a JSON-encoded [ApplicationToken] of the top 3 apps detected
/// by the DAR extension. Used ONCE for auto-selection, then the host
/// persists the tokens and tracks them via dedicated DAM events.
struct AutoPickedTokensKey: PreferenceKey {
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

struct HistoryKey: PreferenceKey {
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

