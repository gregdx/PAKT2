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

struct HistoryKey: PreferenceKey {
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

