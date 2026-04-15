import DeviceActivity
import Foundation
import Security

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let defaults = UserDefaults(suiteName: "group.com.PAKT2")
    private let keychainGroup = "9U5UZW39LQ.com.PAKT2"
    private let backendBaseURL = "https://pakt-api.fly.dev/v1"

    // Calibration factor — Apple's DAM overcounts real usage by ~30% (FB15103784).
    // Must stay in sync with ScreenTimeManager2.calibrationFactor. Source of
    // truth: the main app writes its chosen value into the shared App Group at
    // "pakt_calibration_factor" so the extension can pick it up without
    // needing access to the main bundle's UserDefaults.standard.
    private var calibrationFactor: Double {
        let raw = defaults?.double(forKey: "pakt_calibration_factor") ?? 0
        if raw <= 0 { return 0.70 }
        return min(max(raw, 0.30), 1.00)
    }
    private func calibrate(_ minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return Int((Double(minutes) * calibrationFactor).rounded())
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    // MARK: - Lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let today = Self.dateFmt.string(from: Date())
        let activityRaw = activity.rawValue
        
        // Gestion propre des blocs Opal-style
        if activityRaw.hasPrefix("pakt_block_") {
            let blockNum = activityRaw.replacingOccurrences(of: "pakt_block_", with: "")
            let blockKey = "block_\(blockNum)"
            let blockDateKey = "\(blockKey)_date"
            
            if defaults?.string(forKey: blockDateKey) != today {
                defaults?.set(0, forKey: blockKey)
                defaults?.set(today, forKey: blockDateKey)
                defaults?.removeObject(forKey: "\(blockKey)_last_fire_epoch")
            }
        }
        
        defaults?.set("Start \(activityRaw) @ \(Self.timeFmt.string(from: Date()))", forKey: "monitor_debug_last_interval_start")
        defaults?.synchronize()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        let raw = event.rawValue
        let today = Self.dateFmt.string(from: Date())
        let nowEpoch = Date().timeIntervalSince1970

        // Rollover: si shared_today tient encore la valeur finale d'un jour
        // précédent, la persister dans shared_history avant écrasement.
        if let prevDate = defaults?.string(forKey: "shared_today_date"),
           prevDate != today,
           let prevValue = defaults?.integer(forKey: "shared_today"), prevValue > 0 {
            appendToSharedHistory(date: prevDate, minutes: prevValue)
        }

        defaults?.set("\(raw) @ \(Self.timeFmt.string(from: Date()))", forKey: "monitor_debug_last_event")

        // --- CAS 1 : TRACKING PAR APP (Format: app{idx}_{mins}) ---
        if raw.hasPrefix("app"), let underscoreIdx = raw.firstIndex(of: "_") {
            handlePerAppThreshold(raw: raw, underscoreIdx: underscoreIdx, today: today)
            notifyMainApp()
            return
        }

        // --- CAS 2 : TRACKING GLOBAL (Format: b{block}_{mins}) ---
        guard let minutes = extractMinutes(from: raw) else { return }
        
        let blockNum = activity.rawValue.replacingOccurrences(of: "pakt_block_", with: "")
        let blockKey = "block_\(blockNum)"
        let lastFireKey = "\(blockKey)_last_fire_epoch"
        
        let existingBlockValue = (defaults?.string(forKey: "\(blockKey)_date") == today) ? (defaults?.integer(forKey: blockKey) ?? 0) : 0
        let lastFireEpoch = (defaults?.string(forKey: "\(blockKey)_date") == today) ? (defaults?.double(forKey: lastFireKey) ?? 0) : 0

        var cappedValue = min(max(existingBlockValue, minutes), 120)

        // PROTECTION CONTRE BUG APPLE (Sauts de temps fantômes)
        if existingBlockValue > 0, lastFireEpoch > 0, minutes > existingBlockValue {
            let secondsElapsed = nowEpoch - lastFireEpoch
            let minutesElapsed = Int(ceil(secondsElapsed / 60.0))
            
            // On accorde +3 min de tolérance (Apple groupe parfois les events)
            let wallClockCap = existingBlockValue + minutesElapsed + 3
            
            if cappedValue > wallClockCap {
                defaults?.set("Cap applied to \(raw): \(cappedValue)->\(wallClockCap)", forKey: "monitor_debug_last_cap")
                cappedValue = min(wallClockCap, 120)
            }
        }

        // Sauvegarde du bloc
        defaults?.set(cappedValue, forKey: blockKey)
        defaults?.set(today, forKey: "\(blockKey)_date")
        defaults?.set(nowEpoch, forKey: lastFireKey)

        // CALCUL DU TOTAL JOURNALIER (Somme des blocs) — valeur RAW de l'OS
        var rawDailyTotal = 0
        for i in 0..<12 {
            if defaults?.string(forKey: "block_\(i)_date") == today {
                rawDailyTotal += defaults?.integer(forKey: "block_\(i)") ?? 0
            }
        }

        // Calibration (×0.70 par défaut) appliquée AVANT d'écrire aux
        // consommateurs en aval. Le main app garde aussi un calibrate() en
        // safety net, mais la source de vérité partagée est déjà corrigée ici.
        let dailyTotal = calibrate(rawDailyTotal)

        // Mise à jour finale
        defaults?.set(dailyTotal, forKey: "shared_today")
        defaults?.set(today, forKey: "shared_today_date")
        defaults?.set(rawDailyTotal, forKey: "shared_today_raw") // debug
        defaults?.synchronize()

        keychainWrite("shared_today", value: "\(dailyTotal)")
        keychainWrite("shared_today_date", value: today)

        // SYNC DIRECT AVEC LES AMIS (valeur calibrée)
        syncToBackend(minutes: dailyTotal, date: today)
        
        notifyMainApp()
    }

    // MARK: - Logic Helpers

    private func handlePerAppThreshold(raw: String, underscoreIdx: String.Index, today: String) {
        let idxPart = String(raw[raw.index(raw.startIndex, offsetBy: 3)..<underscoreIdx])
        let minsPart = String(raw[raw.index(after: underscoreIdx)...])
        
        guard let idx = Int(idxPart), let mins = Int(minsPart) else { return }
        
        let key = "app\(idx)_today"
        let dateKey = "\(key)_date"
        
        // On prend le max pour être sûr de ne pas reculer si iOS envoie les events dans le désordre
        let existing = (defaults?.string(forKey: dateKey) == today) ? (defaults?.integer(forKey: key) ?? 0) : 0
        defaults?.set(max(existing, mins), forKey: key)
        defaults?.set(today, forKey: dateKey)
    }

    private func extractMinutes(from raw: String) -> Int? {
        if raw.hasPrefix("b"), let lastPart = raw.split(separator: "_").last {
            return Int(lastPart)
        } else if raw.hasPrefix("threshold_") {
            return Int(raw.replacingOccurrences(of: "threshold_", with: ""))
        }
        return nil
    }

    /// Append une entrée "date:minutes" à la clé App Group "shared_history".
    /// Format CSV: "2026-04-12:240,2026-04-11:190". Upsert en prenant le max.
    private func appendToSharedHistory(date: String, minutes: Int) {
        let existing = defaults?.string(forKey: "shared_history") ?? ""
        var byDate: [String: Int] = [:]
        for entry in existing.split(separator: ",") {
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let m = Int(parts[1]) else { continue }
            byDate[String(parts[0])] = m
        }
        byDate[date] = max(byDate[date] ?? 0, minutes)
        let raw = byDate.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        defaults?.set(raw, forKey: "shared_history")
        defaults?.synchronize()
    }

    private func notifyMainApp() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName("com.PAKT2.screenTimeUpdate" as CFString), nil, nil, true)
    }

    // MARK: - Backend Sync (Direct)

    private func syncToBackend(minutes: Int, date: String) {
        guard let token = keychainRead("pakt_extension_token") else { return }

        let body: [String: Any] = [
            "minutes": minutes,
            "date": date,
            "source": "monitor_extension_direct"
        ]

        // IMPORTANT: /scores/correct (direct assign) and NOT /scores/sync
        // (GREATEST). DAM is the sole source of truth post-2026-04-14 so we
        // must be able to correct a previously-inflated value downward.
        guard let url = URL(string: "\(backendBaseURL)/scores/correct"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        // Important: Utiliser une session avec une config "waitsForConnectivity"
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        
        session.dataTask(with: request).resume()
    }

    // MARK: - Keychain Core

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
}
