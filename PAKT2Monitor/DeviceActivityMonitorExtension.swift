import DeviceActivity
import Foundation
import Security

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let defaults = UserDefaults(suiteName: "group.com.PAKT2")
    private let keychainGroup = "9U5UZW39LQ.com.PAKT2"
    private let backendBaseURL = "https://pakt-api.fly.dev/v1"

    // MARK: - Interval lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // New day — reset counter
        defaults?.set(0, forKey: "st_todayMinutes")
        defaults?.synchronize()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // End of day (midnight) — sync the final daily total
        let totalMinutes = defaults?.integer(forKey: "st_todayMinutes") ?? 0
        guard totalMinutes > 0 else { return }

        // intervalDidEnd fires AT midnight → Date() is already the new day
        // These minutes belong to YESTERDAY
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let yesterdayStr = df.string(from: yesterday)
        let yesterdayLabel: String = {
            let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US")
            return f.string(from: yesterday)
        }()

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

    // MARK: - Threshold reached (every 15 min of screen time)

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        var minutes = 0
        if let minutesStr = event.rawValue.split(separator: "_").last, let m = Int(minutesStr) {
            minutes = m
        }

        guard minutes > 0 else { return }
        print("[PAKT Monitor] Threshold reached: \(minutes) min")

        // Écrire dans le Keychain pour que le main app puisse lire via loadProfileCache
        // (vital quand les DARs ne fonctionnent pas)
        keychainWrite("shared_today", value: "\(minutes)")
        keychainWrite("shared_today_date", value: todayDateString)

        // Also update App Group (if it works)
        defaults?.set(minutes, forKey: "shared_today")
        defaults?.set(todayDateString, forKey: "shared_today_date")
        defaults?.synchronize()

        // Sync to backend
        syncToBackend(minutes: minutes, date: todayDateString)

        // Réveiller l'app principale via Darwin notification
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName("com.PAKT2.screenTimeUpdate" as CFString), nil, nil, true)
    }

    // MARK: - Backend REST sync

    private func syncToBackend(minutes: Int, date: String) {
        guard let token = keychainRead("pakt_extension_token") else {
            print("[PAKT Monitor] No extension token in Keychain — can't sync")
            return
        }
        print("[PAKT Monitor] Syncing \(minutes) min to backend...")

        let body: [String: Any] = [
            "minutes": minutes,
            "social_minutes": 0,
            "date": date
        ]

        guard let url = URL(string: "\(backendBaseURL)/scores/sync"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        // Fire and forget — we're in an extension, use a semaphore to wait
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
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
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var dayLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
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
