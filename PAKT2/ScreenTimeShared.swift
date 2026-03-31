import Foundation
import SwiftUI

// Constantes partagées entre l'app et l'extension Report
enum ScreenTimeShared {
    static let appGroupID       = "group.com.PAKT2"
    static let reportMinutesKey = "report_minutes"
    static let reportDateKey    = "report_date"
    static let goalMinutesKey   = "goalMinutes"
    static let notifName        = "com.PAKT2.screenTimeUpdate" as CFString
}

// PreferenceKeys
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

struct HistoryKey: PreferenceKey {
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

