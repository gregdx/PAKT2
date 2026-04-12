import DeviceActivity
import Foundation
import Security

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let defaults = UserDefaults(suiteName: "group.com.PAKT2")
    // Keep in sync with AppConfig in SharedComponents2.swift
    private let keychainGroup = "9U5UZW39LQ.com.PAKT2"
    private let backendBaseURL = "https://pakt-api.fly.dev/v1"

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US"); return f
    }()

    // MARK: - Interval lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let today = Self.dateFmt.string(from: Date())

        // Reset ONLY this block's counter (not the daily total or other blocks).
        // Each 2h block resets independently when its interval starts.
        let activityRaw = activity.rawValue
        if activityRaw.hasPrefix("pakt_block_") {
            let blockNum = activityRaw.replacingOccurrences(of: "pakt_block_", with: "")
            let blockKey = "block_\(blockNum)"
            let blockDateKey = "\(blockKey)_date"
            let storedDate = defaults?.string(forKey: blockDateKey) ?? ""
            if storedDate != today {
                // New day: reset this block
                defaults?.set(0, forKey: blockKey)
                defaults?.set(today, forKey: blockDateKey)
            }
            // Don't reset shared_today here — it's the SUM of all blocks,
            // computed in eventDidReachThreshold.
        } else {
            // Legacy activity: reset daily total if new day
            let storedDate = defaults?.string(forKey: "shared_today_date") ?? ""
            if storedDate != today {
                defaults?.set(0, forKey: "shared_today")
                defaults?.set(today, forKey: "shared_today_date")
            }
        }

        defaults?.set("intervalDidStart \(activityRaw) @ \(today) \(Self.timeFmt.string(from: Date()))", forKey: "monitor_debug_last_interval_start")
        defaults?.synchronize()
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // End of day (midnight) — sync the final daily total
        let totalMinutes = defaults?.integer(forKey: "shared_today") ?? 0
        guard totalMinutes > 0 else { return }

        // intervalDidEnd fires AT midnight → Date() is already the new day
        // These minutes belong to YESTERDAY
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let yesterdayStr = Self.dateFmt.string(from: yesterday)
        let yesterdayLabel = Self.dayFmt.string(from: yesterday)

        defaults?.set(totalMinutes, forKey: "st_yesterdayMinutes")

        // Update history with YESTERDAY's date
        var history = loadHistory()
        history.removeAll { $0.date == yesterdayStr }
        history.append(DayEntryMonitor(day: yesterdayLabel, date: yesterdayStr, minutes: totalMinutes))
        if history.count > 30 { history = Array(history.suffix(30)) }
        if let data = try? JSONEncoder().encode(history) {
            defaults?.set(data, forKey: "st_history")
        }
        defaults?.synchronize()

        // Sync to backend with YESTERDAY's date
        syncToBackend(minutes: totalMinutes, date: yesterdayStr)
    }

    // MARK: - Threshold reached (Opal-style: 12 blocks × 16 events)

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        // Parse event name "b{block}_{minutes}" (new format)
        // or legacy "threshold_{minutes}" (backward compat)
        let raw = event.rawValue
        var minutes = 0

        if raw.hasPrefix("b") {
            // New format: b0_5, b3_60, etc.
            guard let lastPart = raw.split(separator: "_").last,
                  let m = Int(lastPart), m > 0 else { return }
            minutes = m
        } else if raw.hasPrefix("threshold_") {
            // Legacy format
            guard let m = Int(raw.replacingOccurrences(of: "threshold_", with: "")), m > 0 else { return }
            minutes = m
        } else {
            return
        }

        let now = Self.timeFmt.string(from: Date())
        defaults?.set("\(raw) @ \(now)", forKey: "monitor_debug_last_event")

        let today = todayDateString

        // === Parse event name ===
        // Format: "b{block}_{mins}" for total, "b{block}_a{app}_{mins}" for per-app
        let parts = raw.split(separator: "_")
        var appIdx: Int? = nil
        if parts.count >= 3, parts[1].hasPrefix("a"), let idx = Int(parts[1].dropFirst()) {
            appIdx = idx
        }

        // === Per-block max (idempotent) ===
        let activityRaw = activity.rawValue
        let blockNum = activityRaw.replacingOccurrences(of: "pakt_block_", with: "")

        if let appIdx = appIdx {
            // Per-app event: store per-app per-block max
            let appBlockKey = "app\(appIdx)_block_\(blockNum)"
            let appBlockDateKey = "\(appBlockKey)_date"
            let existing = (defaults?.string(forKey: appBlockDateKey) == today) ? (defaults?.integer(forKey: appBlockKey) ?? 0) : 0
            let appBlockMax = min(max(existing, minutes), 120)
            defaults?.set(appBlockMax, forKey: appBlockKey)
            defaults?.set(today, forKey: appBlockDateKey)

            // Sum this app across all blocks
            var appTotal = 0
            for i in 0..<12 {
                let k = "app\(appIdx)_block_\(i)"
                if defaults?.string(forKey: "\(k)_date") == today {
                    appTotal += defaults?.integer(forKey: k) ?? 0
                }
            }
            defaults?.set(appTotal, forKey: "app\(appIdx)_today")
            defaults?.set(today, forKey: "app\(appIdx)_today_date")
        } else {
            // Total event: store per-block max
            let blockKey = "block_\(blockNum)"
            let blockDateKey = "\(blockKey)_date"
            let existingBlock = (defaults?.string(forKey: blockDateKey) == today) ? (defaults?.integer(forKey: blockKey) ?? 0) : 0
            let blockMax = min(max(existingBlock, minutes), 120)
            defaults?.set(blockMax, forKey: blockKey)
            defaults?.set(today, forKey: blockDateKey)
        }

        // === Sum all blocks for daily total ===
        var dailyTotal = 0
        for i in 0..<12 {
            let bk = "block_\(i)"
            if defaults?.string(forKey: "\(bk)_date") == today {
                dailyTotal += defaults?.integer(forKey: bk) ?? 0
            }
        }

        defaults?.set(dailyTotal, forKey: "shared_today")
        defaults?.set(today, forKey: "shared_today_date")
        defaults?.synchronize()

        keychainWrite("shared_today", value: "\(dailyTotal)")
        keychainWrite("shared_today_date", value: today)

        // Wake main app
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName("com.PAKT2.screenTimeUpdate" as CFString), nil, nil, true)
    }

    // MARK: - Backend REST sync

    private func syncToBackend(minutes: Int, date: String) {
        guard let token = keychainRead("pakt_extension_token") else { return }

        let body: [String: Any] = [
            "minutes": minutes,
            "social_minutes": 0,
            "date": date
        ]

        guard let url = URL(string: "\(backendBaseURL)/scores/sync"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        // Fire and forget — no semaphore to avoid OS killing the extension
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - Keychain

    private func keychainRead(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainGroup
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    // MARK: - Helpers

    private var todayDateString: String {
        Self.dateFmt.string(from: Date())
    }

    private func loadHistory() -> [DayEntryMonitor] {
        guard let data = defaults?.data(forKey: "st_history"),
              let decoded = try? JSONDecoder().decode([DayEntryMonitor].self, from: data) else { return [] }
        return decoded
    }
}

struct DayEntryMonitor: Codable {
    let day: String
    let date: String
    let minutes: Int
}
