import Foundation
import DeviceActivity

// MARK: - Constantes partagées entre l'app et les extensions

enum ScreenTimeShared {
    static let appGroupID = "group.com.PAKT"

    // Clés UserDefaults dans le shared container
    static let todayMinutesKey     = "st_todayMinutes"
    static let yesterdayMinutesKey  = "st_yesterdayMinutes"
    static let lastUpdateKey       = "st_lastUpdate"
    static let weekHistoryKey      = "st_weekHistory"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // Sauvegarder les données depuis l'extension
    static func saveScreenTime(todayMinutes: Int, history: [DayEntry]) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(todayMinutes, forKey: todayMinutesKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: weekHistoryKey)
        }
        defaults.synchronize()
    }

    // Lire les données depuis l'app principale
    static func readScreenTime() -> (todayMinutes: Int, history: [DayEntry], lastUpdate: Date?) {
        guard let defaults = sharedDefaults else { return (0, [], nil) }
        let minutes = defaults.integer(forKey: todayMinutesKey)
        let ts = defaults.double(forKey: lastUpdateKey)
        let lastUpdate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil

        var history: [DayEntry] = []
        if let data = defaults.data(forKey: weekHistoryKey),
           let decoded = try? JSONDecoder().decode([DayEntry].self, from: data) {
            history = decoded
        }
        return (minutes, history, lastUpdate)
    }
}

// Structure simple Codable pour le partage via App Group
struct DayEntry: Codable {
    let day: String       // "Mon", "Tue", etc.
    let date: String      // "2026-03-16"
    let minutes: Int
}

// NOTE: DeviceActivityReport.Context est défini dans TotalActivityReport.swift
// (extension PAKT2Report) car ce type n'est pas accessible depuis l'app principale.

// MARK: - DeviceActivity schedule helper

extension DeviceActivitySchedule {
    /// Schedule qui couvre la journée entière, se répète chaque jour
    static var daily: DeviceActivitySchedule {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: calendar.startOfDay(for: Date()))
        var end = DateComponents()
        end.hour = 23
        end.minute = 59
        return DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )
    }
}
