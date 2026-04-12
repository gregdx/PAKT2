import SwiftUI
import Combine
import FamilyControls
import DeviceActivity
import ManagedSettings
import Security

struct ProfileDayData: Identifiable {
    let id = UUID()
    let label: String   // "Mon", "Tue"…
    let date: String    // "yyyy-MM-dd"
    let minutes: Int
}

final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published var isAuthorized: Bool = false

    private let center = AuthorizationCenter.shared

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US"); return f
    }()

    // MARK: - Profile stats cache (alimenté par URL schemes depuis l'extension)

    @Published var profileToday: Int = 0
    private var displayedToday: Int = 0  // Never decreases within a session
    @Published var profileWeekAvg: Int = 0
    @Published var profileMonthAvg: Int = 0
    @Published var profileHistory: [ProfileDayData] = []
    @Published var categorySocial: Int = 0
    @Published var perAppMinutes: [(index: Int, minutes: Int)] = []
    @Published var trackedAppMinutes: Int = 0  // Per-app tracking total for scope=.apps groups
    @Published var currentStreak: Int = 0
    @Published var memberStreaks: [String: Int] = [:]
    @Published var memberLastSync: [String: Date] = [:]
    @Published var darDebugInfo: String = "never"
    @Published var todaySourceInfo: String = "none"
    @Published var familySelection: FamilyActivitySelection = ScreenTimeManager.loadSelection()

    // MARK: - Per-app tracking (for scope="apps" groups + Profile breakdown)
    //
    // The user can additionally pick up to MAX_TRACKED_APPS individual apps
    // (Instagram, TikTok, etc.). The Monitor schedules a dedicated
    // DeviceActivityEvent per picked app so DAM fires per-app thresholds
    // and writes minutes into `app{i}_today` in App Group.
    @Published var trackedAppsSelection: FamilyActivitySelection = ScreenTimeManager.loadTrackedAppsSelection()

    /// Ordered snapshot of the tokens from trackedAppsSelection. The index in
    /// this array maps 1-to-1 with the `app{i}_today` keys written by the
    /// Monitor extension. Persisted so host + extension agree on index.
    @Published private(set) var trackedAppsTokens: [ApplicationToken] = ScreenTimeManager.loadTrackedAppsTokens()

    struct PerAppEntry: Identifiable {
        let index: Int
        let token: ApplicationToken
        let minutes: Int
        var id: Int { index }
    }

    /// Calibrated per-app minutes for today, sorted desc, zeros filtered out.
    @Published var perAppBreakdown: [PerAppEntry] = []

    static let MAX_TRACKED_APPS = 10
    static let streakGoalMinutes = 180

    private static let trackedAppsKey = "pakt_tracked_apps_selection"
    private static let trackedAppsTokensKey = "pakt_tracked_apps_tokens"

    static func loadTrackedAppsSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: trackedAppsKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    static func loadTrackedAppsTokens() -> [ApplicationToken] {
        guard let data = UserDefaults.standard.data(forKey: trackedAppsTokensKey),
              let decoded = try? JSONDecoder().decode([ApplicationToken].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Save a new per-app selection. Caps at MAX_TRACKED_APPS to stay within
    /// DAM's 20-events-per-schedule budget. Clears stale per-app counters and
    /// restarts background monitoring so the Monitor picks up the new list.
    func saveTrackedAppsSelection(_ selection: FamilyActivitySelection) {
        let tokens = Array(selection.applicationTokens.prefix(Self.MAX_TRACKED_APPS))
        let trimmed = FamilyActivitySelection()
        var trimmedMut = trimmed
        trimmedMut.applicationTokens = Set(tokens)

        trackedAppsSelection = trimmedMut
        trackedAppsTokens = tokens

        if let sdata = try? JSONEncoder().encode(trimmedMut) {
            UserDefaults.standard.set(sdata, forKey: Self.trackedAppsKey)
            sharedUD?.set(sdata, forKey: Self.trackedAppsKey)
        }
        if let tdata = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(tdata, forKey: Self.trackedAppsTokensKey)
            sharedUD?.set(tdata, forKey: Self.trackedAppsTokensKey)
        }
        sharedUD?.set(tokens.count, forKey: "tracked_app_count")

        // Wipe per-app counters so the new selection starts fresh.
        for i in 0..<Self.MAX_TRACKED_APPS {
            sharedUD?.removeObject(forKey: "app\(i)_today")
            sharedUD?.removeObject(forKey: "app\(i)_today_date")
            for b in 0..<12 {
                sharedUD?.removeObject(forKey: "app\(i)_block_\(b)")
                sharedUD?.removeObject(forKey: "app\(i)_block_\(b)_date")
            }
        }
        sharedUD?.synchronize()

        perAppBreakdown = []
        Log.d("[ScreenTime] Saved tracked apps selection: \(tokens.count) apps")
        startBackgroundMonitoring(force: true)
    }


    // MARK: - Calibration factor
    //
    // Apple's DeviceActivityMonitor is known to overcount real usage by ~30%
    // (FB15103784 + multiple iOS 17/18/26 threads). The bug has several causes:
    // premature threshold fires, Safari double-counting, cross-device bleed
    // even with "Share Across Devices" off, and time counted while the device
    // is locked / on Home screen. Apps like Opal get closer to reality by
    // filtering out passive time, but DAM exposes no such filter to us.
    //
    // As a pragmatic workaround, every raw minute read from App Group / Keychain
    // is multiplied by this factor before being surfaced to the UI and the
    // backend sync. The default 0.70 matches the 70-78% overcount we measured
    // on Apr 10. Users can tune it in Settings if their particular phone
    // is closer to Apple's native figure.
    static let calibrationKey = "pakt_calibration_factor"
    static var calibrationFactor: Double {
        let raw = UserDefaults.standard.double(forKey: calibrationKey)
        // clamp to [0.30, 1.00] so a typo can't zero out scores or inflate them
        if raw <= 0 { return 0.70 }
        return min(max(raw, 0.30), 1.00)
    }
    static func setCalibrationFactor(_ value: Double) {
        let clamped = min(max(value, 0.30), 1.00)
        UserDefaults.standard.set(clamped, forKey: calibrationKey)
    }
    private func calibrate(_ minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return Int((Double(minutes) * Self.calibrationFactor).rounded())
    }

    // MARK: - FamilyActivitySelection persistence (for DeviceActivityMonitor thresholds)

    private static let selectionKey = "pakt_family_selection"

    static func loadSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: selectionKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection(includeEntireCategory: true)
        }
        return decoded
    }

    func saveFamilySelection(_ selection: FamilyActivitySelection) {
        familySelection = selection
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: Self.selectionKey)
            UserDefaults(suiteName: "group.com.PAKT2")?.set(data, forKey: Self.selectionKey)
        }
        // Clear stale threshold values from previous selection so the new
        // selection can start fresh (old max() logic would block lower values).
        profileToday = 0
        UserDefaults.standard.removeObject(forKey: UDKey.todayMinutes)
        UserDefaults.standard.removeObject(forKey: UDKey.todayDate)
        sharedUD?.removeObject(forKey: "shared_today")
        sharedUD?.removeObject(forKey: "shared_today_date")
        keychainDelete("shared_today")
        keychainDelete("shared_today_date")
        Log.d("[ScreenTime] Saved family selection: apps=\(selection.applicationTokens.count) cats=\(selection.categoryTokens.count), cleared caches")
        // Force restart — user explicitly changed selection, bypass debounce
        startBackgroundMonitoring(force: true)
    }

    private func keychainDelete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: AppConfig.keychainGroup
        ]
        SecItemDelete(query as CFDictionary)
    }

    var hasFamilySelection: Bool {
        !familySelection.applicationTokens.isEmpty
            || !familySelection.categoryTokens.isEmpty
            || !familySelection.webDomainTokens.isEmpty
    }

    private var syncTask: Task<Void, Never>?
    private var fetchCumulativeTask: Task<Void, Never>?
    private var lastSyncDate: Date = .distantPast
    var lastFetchDate: Date = .distantPast

    init() {
        isAuthorized = center.authorizationStatus == .approved
        runMigrationV2IfNeeded()
        runMigrationV3IfNeeded()
        runMigrationV4ReaderReset()
        loadProfileCache()
        registerDarwinNotification()
    }

    /// One-shot migration v4: purge ALL stale screen time data when switching
    /// to the new Opal-style 12-block reader. Old DAM/DAR values are inaccurate
    /// and must not contaminate the new reader's fresh start.
    private func runMigrationV4ReaderReset() {
        let key = "pakt_migration_v4_reader_reset"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        // Purge everything
        let today = Self.dateFormatter.string(from: Date())
        sharedUD?.set(0, forKey: "shared_today")
        sharedUD?.set(today, forKey: "shared_today_date")
        sharedUD?.removeObject(forKey: "st_history")
        sharedUD?.removeObject(forKey: "shared_history")
        sharedUD?.synchronize()
        UserDefaults.standard.set(0, forKey: UDKey.todayMinutes)
        UserDefaults.standard.set(today, forKey: UDKey.todayDate)
        UserDefaults.standard.removeObject(forKey: UDKey.historyRaw)
        UserDefaults.standard.removeObject(forKey: UDKey.weekAvg)
        UserDefaults.standard.removeObject(forKey: UDKey.monthAvg)
        UserDefaults.standard.removeObject(forKey: "pakt_week_history")
        keychainDelete("shared_today")
        keychainDelete("shared_today_date")
        keychainDelete("shared_history")
        UserDefaults.standard.set(true, forKey: key)
        Log.d("[PAKT Migration v4] Purged all stale data for new 12-block reader")
    }

    /// One-shot migration v3: wipe stale shared_today after the brief 3-tier
    /// DAM experiment inflated it. The 3-tier config (3 parallel schedules)
    /// caused Apple to overcount ~18%, and the inflated value sticks via max()
    /// even after reverting to single-tier. This migration wipes it so the
    /// next cascade writes the correct current value.
    private func runMigrationV3IfNeeded() {
        let migrationKey = "pakt_migration_v3_clear_tier_experiment"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        sharedUD?.removeObject(forKey: "shared_today")
        sharedUD?.removeObject(forKey: "shared_today_date")
        sharedUD?.synchronize()
        keychainDelete("shared_today")
        keychainDelete("shared_today_date")
        UserDefaults.standard.set(true, forKey: migrationKey)
        Log.d("[PAKT Migration v3] Cleared shared_today inflated by brief 3-tier DAM experiment")
    }

    /// One-shot migration: wipe stale shared_today values previously written
    /// by the Monitor extension (which overcounted ~70% per Apple-confirmed
    /// bug). DAR is now the sole source of truth via TodayMinutesKey bridge.
    private func runMigrationV2IfNeeded() {
        let migrationKey = "pakt_migration_v2_dar_authoritative"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        sharedUD?.removeObject(forKey: "shared_today")
        sharedUD?.removeObject(forKey: "shared_today_date")
        sharedUD?.removeObject(forKey: "shared_social")
        sharedUD?.removeObject(forKey: "shared_social_date")
        sharedUD?.synchronize()
        keychainDelete("shared_today")
        keychainDelete("shared_today_date")
        keychainDelete("shared_social")
        keychainDelete("shared_social_date")
        UserDefaults.standard.set(true, forKey: migrationKey)
        Log.d("[PAKT Migration v2] Cleared stale shared_today from Keychain + App Group")
    }

    /// Écoute les Darwin notifications postées par les extensions DAR/Monitor
    /// pour relire immédiatement les données du App Group / Keychain
    private var lastDarwinNotif: Date = .distantPast
    private func registerDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let mgr = Unmanaged<ScreenTimeManager>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    // Debounce: the Monitor may post many Darwin notifications
                    // in rapid succession (one per threshold). Only process one per second.
                    let now = Date()
                    guard now.timeIntervalSince(mgr.lastDarwinNotif) > 1.0 else { return }
                    mgr.lastDarwinNotif = now
                    Log.d("[PAKT] Darwin notification — reload")
                    mgr.loadProfileCache()
                    mgr.updateLocalGroups(appState: AppState.shared)
                    mgr.syncToBackend(appState: AppState.shared)
                }
            },
            "com.PAKT2.screenTimeUpdate" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private let sharedUD = UserDefaults(suiteName: "group.com.PAKT2")

    // Lire depuis le Keychain (partagé entre app et extension)
    private let keychainGroup = AppConfig.keychainGroup

    private func keychainRead(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainInt(_ key: String) -> Int {
        Int(keychainRead(key) ?? "") ?? 0
    }

    func loadProfileCache() {
        // Force App Group to re-read from disk (the monitor extension writes
        // from a different process — without synchronize the host reads stale cache)
        sharedUD?.synchronize()

        let today = Self.dateFormatter.string(from: Date())
        var todaySource = "none"
        var socialSource = "none"
        var weekSource = "none"
        var monthSource = "none"

        // Read ALL sources and take the MAX so fresher values from Monitor extension
        // (via keychain/app group) always beat stale UserDefaults.standard values.

        // === 1. Cache standard ===
        let stdToday: Int = {
            guard UserDefaults.standard.string(forKey: UDKey.todayDate) == today else { return 0 }
            return UserDefaults.standard.integer(forKey: UDKey.todayMinutes)
        }()
        let stdSocial: Int = {
            guard UserDefaults.standard.string(forKey: UDKey.catSocialDate) == today else { return 0 }
            return UserDefaults.standard.integer(forKey: UDKey.catSocial)
        }()

        // === 2. App Group (written by Monitor extension) ===
        let agToday: Int = {
            let v = sharedUD?.integer(forKey: "shared_today") ?? 0
            let d = sharedUD?.string(forKey: "shared_today_date") ?? ""
            return (v > 0 && d == today) ? v : 0
        }()
        let agSocial: Int = {
            let v = sharedUD?.integer(forKey: "shared_social") ?? 0
            let d = sharedUD?.string(forKey: "shared_social_date") ?? ""
            return (v > 0 && d == today) ? v : 0
        }()

        // === 3. Keychain (fallback for when App Group is broken) ===
        let kcToday: Int = {
            let v = keychainInt("shared_today")
            let d = keychainRead("shared_today_date") ?? ""
            return (v > 0 && d == today) ? v : 0
        }()
        let kcSocial: Int = {
            let v = keychainInt("shared_social")
            let d = keychainRead("shared_social_date") ?? ""
            return (v > 0 && d == today) ? v : 0
        }()


        // DAR exact value is NOT accessible from the host app — DAR extension
        // sandbox blocks ALL IPC channels (confirmed 2026-04-12). The DAR view
        // on the profile renders exact minutes as pixels (display-only).
        // For backend/social features, DAM thresholds (±15 min) are the only
        // data source. This is how every Screen Time app works (Opal, UseLess,
        // ScreenZen). The overcount is an Apple bug (FB15103784), not ours.
        // ONLY read from App Group (written by the 12-block reader).
        // Apply the calibration factor to compensate for Apple's DAM overcount.
        profileToday = calibrate(agToday)
        todaySource = agToday > 0 ? "reader" : "none"

        // Live interpolation: if the app is in foreground, the user IS using
        // their phone. Add elapsed minutes since the last threshold fire.
        // This gives ~1 min visual updates between 5-min threshold jumps.
        if agToday > 0, let lastEventStr = sharedUD?.string(forKey: "monitor_debug_last_event") {
            // Parse "b7_45 @ 18:32:15" → extract time
            let parts = lastEventStr.split(separator: "@")
            if parts.count == 2 {
                let timePart = parts[1].trimmingCharacters(in: .whitespaces)
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm:ss"
                if let eventTime = fmt.date(from: timePart) {
                    let cal = Calendar.current
                    let now = Date()
                    // Build today's date with the event time
                    var comps = cal.dateComponents([.year, .month, .day], from: now)
                    let eventComps = cal.dateComponents([.hour, .minute, .second], from: eventTime)
                    comps.hour = eventComps.hour
                    comps.minute = eventComps.minute
                    comps.second = eventComps.second
                    if let fullEventTime = cal.date(from: comps) {
                        let elapsed = Int(now.timeIntervalSince(fullEventTime) / 60)
                        if elapsed > 0 && elapsed < 10 {
                            // Interpolated minutes are real wall-clock time the
                            // user has had the app open — no Apple overcount to
                            // correct here. Add raw.
                            profileToday += elapsed
                        }
                    }
                }
            }
        }

        // Never let displayed value decrease (prevents flicker from interpolation jitter)
        profileToday = max(profileToday, displayedToday)
        displayedToday = profileToday
        categorySocial = max(stdSocial, agSocial, kcSocial)

        if categorySocial == stdSocial && categorySocial > 0 { socialSource = "ud_standard" }
        if categorySocial == agSocial && categorySocial > 0 { socialSource = "app_group" }
        if categorySocial == kcSocial && categorySocial > 0 { socialSource = "keychain" }

        // === Per-app daily totals from the 12-block reader ===
        let trackedCount = sharedUD?.integer(forKey: "tracked_app_count") ?? 0
        var appTotals: [(index: Int, minutes: Int)] = []
        var breakdown: [PerAppEntry] = []
        let tokens = trackedAppsTokens
        for i in 0..<trackedCount {
            let key = "app\(i)_today"
            let dateKey = "\(key)_date"
            let d = sharedUD?.string(forKey: dateKey) ?? ""
            let rawM = (d == today) ? (sharedUD?.integer(forKey: key) ?? 0) : 0
            let m = calibrate(rawM)
            if m > 0 { appTotals.append((i, m)) }
            if m > 0, i < tokens.count {
                breakdown.append(PerAppEntry(index: i, token: tokens[i], minutes: m))
            }
        }
        appTotals.sort { $0.minutes > $1.minutes }
        breakdown.sort { $0.minutes > $1.minutes }
        perAppMinutes = appTotals
        perAppBreakdown = breakdown

        profileWeekAvg = UserDefaults.standard.integer(forKey: UDKey.weekAvg)
        profileMonthAvg = UserDefaults.standard.integer(forKey: UDKey.monthAvg)
        if profileWeekAvg > 0 { weekSource = "ud_standard" }
        if profileMonthAvg > 0 { monthSource = "ud_standard" }

        if profileWeekAvg == 0 {
            let v = sharedUD?.integer(forKey: "shared_weekavg") ?? 0
            if v > 0 { profileWeekAvg = v; weekSource = "app_group" }
        }
        if profileMonthAvg == 0 {
            let v = sharedUD?.integer(forKey: "shared_monthavg") ?? 0
            if v > 0 { profileMonthAvg = v; monthSource = "app_group" }
        }
        if trackedAppMinutes == 0 {
            let v = sharedUD?.integer(forKey: "shared_tracked") ?? 0
            let d = sharedUD?.string(forKey: "shared_tracked_date") ?? ""
            if v > 0 && d == today { trackedAppMinutes = v }
        }

        // === 3. Fallback: Keychain ===

        if profileToday == 0 {
            let v = keychainInt("shared_today")
            let d = keychainRead("shared_today_date") ?? ""
            if v > 0 && d == today { profileToday = calibrate(v); todaySource = "keychain" }
        }
        if categorySocial == 0 {
            let v = keychainInt("shared_social")
            let d = keychainRead("shared_social_date") ?? ""
            if v > 0 && d == today { categorySocial = calibrate(v); socialSource = "keychain" }
        }
        if profileWeekAvg == 0 {
            let v = keychainInt("shared_weekavg")
            if v > 0 { profileWeekAvg = v; weekSource = "keychain" }
        }
        if profileMonthAvg == 0 {
            let v = keychainInt("shared_monthavg")
            if v > 0 { profileMonthAvg = v; monthSource = "keychain" }
        }

        let darDebug = keychainRead("dar_debug") ?? "never"
        darDebugInfo = darDebug
        todaySourceInfo = todaySource
        Log.d("[PAKT loadProfileCache] today=\(profileToday)(\(todaySource)) social=\(categorySocial)(\(socialSource)) weekAvg=\(profileWeekAvg)(\(weekSource)) monthAvg=\(profileMonthAvg)(\(monthSource)) | DAR=\(darDebug)")

        // Monitor telemetry — shows whether the Monitor extension's callbacks
        // are actually firing. If these stay "never" while the user actively
        // uses their phone, Monitor isn't receiving events at all.
        let monitorLastEvent = sharedUD?.string(forKey: "monitor_debug_last_event") ?? "never"
        let monitorIntervalStart = sharedUD?.string(forKey: "monitor_debug_last_interval_start") ?? "never"
        Log.d("[PAKT Monitor Debug] last_event=\(monitorLastEvent) | interval_start=\(monitorIntervalStart)")

        // Si on a récupéré des données via fallback, les sauver dans le cache standard + sync
        if profileToday > 0 && UserDefaults.standard.string(forKey: UDKey.todayDate) != today {
            UserDefaults.standard.set(profileToday, forKey: UDKey.todayMinutes)
            UserDefaults.standard.set(today, forKey: UDKey.todayDate)
            syncToBackend(appState: AppState.shared)
        }
        if categorySocial > 0 && UserDefaults.standard.string(forKey: UDKey.catSocialDate) != today {
            UserDefaults.standard.set(categorySocial, forKey: UDKey.catSocial)
            UserDefaults.standard.set(today, forKey: UDKey.catSocialDate)
        }

        // History — ONLY from the new reader. Build chart from profileToday
        // (which was just set above from App Group = reader data).
        // Don't merge old sources — they're stale.
        buildHistoryFromMap([:])
    }

    func updateProfileToday(_ minutes: Int) {
        profileToday = minutes
        // Propager immédiatement aux groupes pour cohérence profil ↔ groupe
        updateLocalGroups(appState: AppState.shared)
    }

    func updateProfileWeekAvg(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: UDKey.weekAvg)
        profileWeekAvg = minutes
    }

    func updateProfileMonthAvg(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: UDKey.monthAvg)
        profileMonthAvg = minutes
    }

    func updateCategorySocial(_ minutes: Int) {
        let today = Self.dateFormatter.string(from: Date())
        UserDefaults.standard.set(minutes, forKey: UDKey.catSocial)
        UserDefaults.standard.set(today, forKey: UDKey.catSocialDate)
        categorySocial = minutes
        updateLocalGroups(appState: AppState.shared)
    }

    func updateProfileHistory(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: UDKey.historyRaw)
        rebuildHistory(from: raw)

        // CRITICAL: use today's history value as the source of truth for profileToday
        // The chart DAR extension writes accurate per-day data. If we can't get
        // TodayMinutesKey to bridge, we extract today from HistoryKey (which works).
        let todayKey = Self.dateFormatter.string(from: Date())
        let byDate = parseHistoryCSV(raw)
        if let todayMins = byDate[todayKey], todayMins > profileToday {
            profileToday = todayMins
            UserDefaults.standard.set(todayMins, forKey: UDKey.todayMinutes)
            UserDefaults.standard.set(todayKey, forKey: UDKey.todayDate)
            Log.d("[ScreenTime] profileToday updated from HistoryKey: \(todayMins) min")
            updateLocalGroups(appState: AppState.shared)
            syncToBackend(appState: AppState.shared)
        }
    }

    /// Injecte le score du jour dans l'historique existant (appelé depuis onOpenURL screentime)
    func injectTodayIntoHistory(date: String, minutes: Int) {
        let existing = UserDefaults.standard.string(forKey: UDKey.historyRaw) ?? ""
        var byDate = parseHistoryCSV(existing)
        byDate[date] = max(byDate[date] ?? 0, minutes)
        let raw = byDate.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: UDKey.historyRaw)
        rebuildHistory(from: raw)
    }

    /// Parse "2026-03-01:120,2026-03-02:90" → ["2026-03-01": 120, "2026-03-02": 90]
    private func parseHistoryCSV(_ raw: String) -> [String: Int] {
        var byDate: [String: Int] = [:]
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let m = Int(parts[1]), m > 0 else { continue }
            byDate[String(parts[0])] = m
        }
        return byDate
    }

    private func mergeHistoryRaw(_ sources: [String]) -> String {
        var byDate: [String: Int] = [:]
        for source in sources {
            for (date, mins) in parseHistoryCSV(source) {
                byDate[date] = max(byDate[date] ?? 0, mins)
            }
        }
        guard !byDate.isEmpty else { return "" }
        return byDate.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

    private func rebuildHistory(from raw: String) {
        // DISABLED — old history sources (DAR, WebSocket, openURL) are stale.
        // Chart now only shows data from the new 12-block reader.
        // Today's value is injected by buildHistoryFromMap via profileToday.
        buildHistoryFromMap([:])
    }

    private func buildEmptyHistory() { buildHistoryFromMap([:]) }

    private func buildHistoryFromMap(_ byDate: [String: Int]) {
        // Inject today's reader value (from App Group only — safe, no stale data).
        var merged = byDate
        let today = Self.dateFormatter.string(from: Date())
        if profileToday > 0 {
            merged[today] = max(merged[today] ?? 0, profileToday)
        }
        let cal = Calendar.current
        var result: [ProfileDayData] = []
        for i in (0..<7).reversed() {
            let date = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let dateStr = Self.dateFormatter.string(from: date)
            let label = Self.dayFormatter.string(from: date)
            result.append(ProfileDayData(label: label, date: dateStr, minutes: merged[dateStr] ?? 0))
        }
        profileHistory = result
    }

    // MARK: - Authorization

    @Published var authError: String? = nil
    @Published var pendingAuthRequest: Bool = false

    @MainActor
    func requestAuthorization() async {
        let rawStatus = center.authorizationStatus.rawValue
        Log.d("[PAKT Auth] Current status: \(rawStatus)")
        authError = nil

        // Si déjà approuvé, juste rafraîchir
        if center.authorizationStatus == .approved {
            self.isAuthorized = true
            self.startBackgroundMonitoring()
            Log.d("[PAKT Auth] Already approved — monitoring started")
            return
        }

        do {
            // DOIT être sur le main thread pour que le dialogue système s'affiche
            try await center.requestAuthorization(for: .individual)
            self.isAuthorized = true
            self.authError = nil
            Log.d("[PAKT Auth] Authorized!")
            self.startBackgroundMonitoring()
        } catch {
            Log.d("[PAKT Auth] Failed: \(error)")
            self.isAuthorized = false
            self.authError = error.localizedDescription
        }
    }

    /// Rafraîchir le statut (à appeler quand l'app revient au premier plan)
    func refreshAuthorizationStatus() {
        isAuthorized = center.authorizationStatus == .approved
    }

    // MARK: - Background Monitoring (DeviceActivityMonitor scheduling)

    private var lastBackgroundMonitoringStart: Date = .distantPast

    func startBackgroundMonitoring(force: Bool = false) {
        guard isAuthorized else { return }
        // No family selection check — we track ALL apps without filter.
        // Debounce: only skip if we actually started monitoring within the
        // last 60s AND this isn't a forced restart (e.g., family selection
        // changed explicitly). Failed/skipped starts don't count.
        let now = Date()
        if !force && now.timeIntervalSince(lastBackgroundMonitoringStart) < 60 {
            Log.d("[PAKT Monitor] Skipping restart — debounced (last was \(Int(now.timeIntervalSince(lastBackgroundMonitoringStart)))s ago)")
            return
        }
        let center = DeviceActivityCenter()

        // Stop ALL previously used activity names to guarantee Apple's DAM
        // has no leftover internal state from prior configs (single-tier
        // "daily_screentime", 3-tier experiment dst_fine/mid/coarse, etc).
        // Then start a FRESH activity name "pakt_daily_v2" so Apple's counter
        // starts from zero for this session.
        // One-time reset is handled by migration v4 in init().
        // Don't reset here — it would wipe the reader's live data on every restart.

        // Stop ALL legacy activity names
        var legacyNames: [DeviceActivityName] = [
            .init("daily_screentime"), .init("dst_fine"), .init("dst_mid"),
            .init("dst_coarse"), .init("pakt_daily_v2"),
        ]
        for i in 0..<12 { legacyNames.append(.init("pakt_block_\(i)")) }
        for i in 0..<Self.MAX_TRACKED_APPS { legacyNames.append(.init("pakt_app_\(i)")) }
        center.stopMonitoring(legacyNames)

        // === OPAL-STYLE: 12 × 2h blocks, each with 23 events at 5-min intervals ===
        // This gives ±5 min precision (vs ±15 before) across 276 total events.
        // Blocks DON'T overlap (unlike our old 3-tier experiment) so no accumulation.
        // Daily total = sum of max-threshold per block.
        // Track ALL screen time — use includeEntireCategory selection to cover everything.
        // An event with empty app/category sets monitors NOTHING. We need tokens.
        let allSelection = FamilyActivitySelection(includeEntireCategory: true)
        // Every 5 min up to 80, then every 10 min to 120. Max gap = 5 min for
        // most usage, 10 min only if >80 min in a single 2h block (rare).
        let totalThresholds = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 90, 100, 110, 120]

        var totalEvents = 0
        for block in 0..<12 {
            let startHour = block * 2
            let endHour = startHour + 1

            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: startHour, minute: 0),
                intervalEnd: DateComponents(hour: endHour, minute: 59, second: 59),
                repeats: true
            )

            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

            // Events with ALL categories = tracks ALL screen time
            for mins in totalThresholds {
                let eventName = DeviceActivityEvent.Name("b\(block)_\(mins)")
                events[eventName] = DeviceActivityEvent(
                    categories: allSelection.categoryTokens,
                    threshold: DateComponents(minute: mins),
                    includesPastActivity: false
                )
            }

            do {
                try center.startMonitoring(
                    .init("pakt_block_\(block)"),
                    during: schedule,
                    events: events
                )
                totalEvents += events.count
            } catch {
                Log.d("[PAKT Monitor] Failed to start block \(block): \(error)")
            }
        }
        // === Per-app tracking ===
        // For each tracked app, schedule a standalone daily activity with
        // dedicated thresholds. These run 00:00–23:59:59 and reset with
        // repeats:true so per-app counters start at 0 each day.
        let appThresholds = [5, 15, 30, 45, 60, 90, 120, 180, 240, 300]
        let appSchedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        var perAppEvents = 0
        for (idx, token) in trackedAppsTokens.enumerated() where idx < Self.MAX_TRACKED_APPS {
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for mins in appThresholds {
                let name = DeviceActivityEvent.Name("app\(idx)_\(mins)")
                events[name] = DeviceActivityEvent(
                    applications: [token],
                    threshold: DateComponents(minute: mins),
                    includesPastActivity: false
                )
            }
            do {
                try center.startMonitoring(
                    .init("pakt_app_\(idx)"),
                    during: appSchedule,
                    events: events
                )
                perAppEvents += events.count
            } catch {
                Log.d("[PAKT Monitor] Failed to start per-app \(idx): \(error)")
            }
        }

        lastBackgroundMonitoringStart = Date()
        Log.d("[PAKT Monitor] Started 12 blocks with \(totalEvents) total events + \(trackedAppsTokens.count) apps with \(perAppEvents) per-app events")
    }

    // MARK: - Lire les données (écrites par onOpenURL dans PAKTApp)

    private func readValue(key: String, dateKey: String) -> Int {
        let today = Self.dateFormatter.string(from: Date())
        guard UserDefaults.standard.string(forKey: dateKey) == today else { return 0 }
        return UserDefaults.standard.integer(forKey: key)
    }

    func readTodayMinutes() -> Int { readValue(key: UDKey.todayMinutes, dateKey: UDKey.todayDate) }

    // MARK: - Mettre à jour les scores locaux dans les groupes

    func updateLocalGroups(appState: AppState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [self] in self.updateLocalGroups(appState: appState) }
            return
        }
        let today = profileToday
        let social = categorySocial
        let uid = appState.currentUID
        guard !uid.isEmpty, !appState.groups.isEmpty else { return }

        var didChange = false
        for gi in appState.groups.indices {
            for mi in appState.groups[gi].members.indices {
                if appState.groups[gi].members[mi].uid == uid {
                    // DAR is authoritative for self — direct assign so a corrected
                    // (lower) value can replace a previously-inflated one.
                    if appState.groups[gi].members[mi].todayMinutes != today {
                        appState.groups[gi].members[mi].todayMinutes = today
                        didChange = true
                    }
                    // monthMinutes : plancher = todayMinutes (au minimum, le cumul >= aujourd'hui)
                    if today > 0 && appState.groups[gi].members[mi].monthMinutes < today {
                        appState.groups[gi].members[mi].monthMinutes = today
                        didChange = true
                    }
                    if social > 0 && appState.groups[gi].members[mi].todaySocialMinutes != social {
                        appState.groups[gi].members[mi].todaySocialMinutes = social
                        didChange = true
                    }
                    if social > 0 && appState.groups[gi].members[mi].monthSocialMinutes < social {
                        appState.groups[gi].members[mi].monthSocialMinutes = social
                        didChange = true
                    }
                }
            }
        }
        if didChange { appState.objectWillChange.send() }
    }

    /// Fetch les scores passés depuis le backend et calcule le cumul "since start"
    func fetchSinceStartCumulative(uid: String, appState: AppState, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastFetchDate) > 10 else { return }
        lastFetchDate = now
        fetchCumulativeTask?.cancel()
        fetchCumulativeTask = Task {
            let df = Self.dateFormatter
            let cal = Calendar.current
            let todayStr = df.string(from: Date())
            // Utiliser profileToday/categorySocial (avec fallbacks App Group + Keychain)
            // plutôt que UserDefaults seul qui peut être périmé
            let (localToday, localSocial) = await MainActor.run {
                (self.profileToday, self.categorySocial)
            }

            // Accumulate all member scores for streak computation + profile backfill
            var allMemberScores: [String: [String: Int]] = [:]
            var mySocialByDate: [String: Int] = [:]   // social scores for current user (for profile backfill)
            var lastSyncByMember: [String: Date] = [:]

            // Snapshot les IDs des groupes pour éviter les crashs si la liste change pendant les await
            let groupSnapshots = await MainActor.run {
                appState.groups.map { (id: $0.id, idStr: $0.id.uuidString, startDate: $0.startDate, memberUids: $0.members.map(\.uid)) }
            }

            // Accumuler toutes les updates HORS main thread, puis appliquer en un seul batch
            struct MemberUpdate {
                let groupId: UUID
                let memberUid: String
                let todayMinutes: Int
                let todaySocialMinutes: Int
                let monthMinutes: Int
                let monthSocialMinutes: Int
            }
            var pendingUpdates: [MemberUpdate] = []

            for snap in groupSnapshots {
                let startStr = df.string(from: cal.startOfDay(for: snap.startDate))

                guard let scores = try? await APIClient.shared.getGroupScores(
                    groupID: snap.idStr, since: startStr
                ) else { continue }

                // Cache les usernames et debug
                for s in scores where s.date == todayStr {
                    if let name = s.username, !name.isEmpty { UsernameCache.store(uid: s.userId, name: name) }
                    Log.d("[PAKT Scores] user=\(s.userId.prefix(8)) date=\(s.date) mins=\(s.minutes) social=\(s.socialMinutes)")
                }

                var byUser: [String: [String: (total: Int, social: Int)]] = [:]
                for s in scores {
                    byUser[s.userId, default: [:]][s.date] = (total: s.minutes, social: s.socialMinutes)
                    let existing = allMemberScores[s.userId]?[s.date] ?? 0
                    allMemberScores[s.userId, default: [:]][s.date] = max(existing, s.minutes)
                    // Track social scores for current user (profile backfill)
                    if s.userId == uid && s.socialMinutes > 0 {
                        mySocialByDate[s.date] = max(mySocialByDate[s.date] ?? 0, s.socialMinutes)
                    }
                    if s.submittedAt > (lastSyncByMember[s.userId] ?? .distantPast) {
                        lastSyncByMember[s.userId] = s.submittedAt
                    }
                }

                for memberUid in snap.memberUids {
                    let memberScores = byUser[memberUid] ?? [:]
                    let isMe = memberUid == uid

                    let todayTotal = memberScores[todayStr]?.total ?? 0
                    let todaySocial = memberScores[todayStr]?.social ?? 0
                    // Pour moi : le local (DAR/Monitor) est la source de vérité pour aujourd'hui
                    // Le backend peut avoir une valeur fausse (ex: intervalDidEnd à minuit)
                    // On ne fait max() que si le local est 0 (DAR pas encore passé)
                    let tMins = isMe ? (localToday > 0 ? localToday : todayTotal) : todayTotal
                    let tSoc = isMe ? (localSocial > 0 ? localSocial : todaySocial) : todaySocial

                    var past = memberScores.filter { $0.key >= startStr && $0.key <= todayStr }
                    if isMe {
                        // Pour le cumul : le local écrase le backend pour aujourd'hui
                        if localToday > 0 || localSocial > 0 {
                            past[todayStr] = (
                                total: localToday > 0 ? localToday : (past[todayStr]?.total ?? 0),
                                social: localSocial > 0 ? localSocial : (past[todayStr]?.social ?? 0)
                            )
                        }
                    }
                    let mMins = past.values.map(\.total).reduce(0, +)
                    let mSoc = past.values.map(\.social).reduce(0, +)

                    pendingUpdates.append(MemberUpdate(
                        groupId: snap.id, memberUid: memberUid,
                        todayMinutes: tMins, todaySocialMinutes: tSoc,
                        monthMinutes: mMins, monthSocialMinutes: mSoc
                    ))
                }
            }

            // Appliquer TOUTES les updates en un seul batch sur le main thread
            await MainActor.run {
                for update in pendingUpdates {
                    guard let gi = appState.groups.firstIndex(where: { $0.id == update.groupId }),
                          let mi = appState.groups[gi].members.firstIndex(where: { $0.uid == update.memberUid })
                    else { continue }
                    // max() pour tout le monde — ne jamais régresser la valeur locale avec
                    // un snapshot périmé (le local peut être plus récent grâce au DAR/Monitor)
                    appState.groups[gi].members[mi].todayMinutes = max(appState.groups[gi].members[mi].todayMinutes, update.todayMinutes)
                    appState.groups[gi].members[mi].todaySocialMinutes = max(appState.groups[gi].members[mi].todaySocialMinutes, update.todaySocialMinutes)
                    // monthMinutes: écriture directe — le cumul calculé est autoritaire
                    appState.groups[gi].members[mi].monthMinutes = update.monthMinutes
                    appState.groups[gi].members[mi].monthSocialMinutes = update.monthSocialMinutes
                }
            }

            // Compute streaks for ALL members
            let goldenRule = Self.streakGoalMinutes
            var streaks: [String: Int] = [:]
            for (memberUid, scores) in allMemberScores {
                var streak = 0
                var checkDate = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
                while true {
                    let dateStr = df.string(from: checkDate)
                    guard let mins = scores[dateStr], mins > 0 else { break }
                    if mins <= goldenRule { streak += 1 } else { break }
                    checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                }
                streaks[memberUid] = streak
            }

            // Backfill : uniquement profileToday, categorySocial, et historique ancien (> 7 jours)
            // weekAvg et monthAvg viennent EXCLUSIVEMENT des DARs Apple (WeekAvgScene / MonthAvgScene)
            // L'historique récent (7 derniers jours) vient du DAR WeekChartScene — le backend ne l'écrase pas
            if let myScores = allMemberScores[uid], !myScores.isEmpty {
                let socialScores = mySocialByDate
                await MainActor.run {
                    // Historique : charger l'existant (alimenté par les DARs)
                    let existing = UserDefaults.standard.string(forKey: UDKey.historyRaw) ?? ""
                    var byDate = self.parseHistoryCSV(existing)

                    // Le DAR WeekChart couvre les 7 derniers jours — ne pas écraser avec le backend
                    let sevenDaysAgo = df.string(from: cal.date(byAdding: .day, value: -7, to: Date()) ?? Date())
                    for (date, minutes) in myScores where minutes > 0 {
                        if date == todayStr {
                            // Aujourd'hui : JAMAIS backfill depuis le backend (peut venir d'un autre device)
                            continue
                        } else if date >= sevenDaysAgo {
                            // Jours récents : ne backfill QUE si aucune donnée locale (DAR pas encore passé)
                            if byDate[date] == nil || byDate[date] == 0 {
                                byDate[date] = minutes
                            }
                        } else {
                            // Jours anciens (> 7j) : le backend est la seule source
                            byDate[date] = max(byDate[date] ?? 0, minutes)
                        }
                    }
                    // Toujours forcer la valeur locale pour aujourd'hui
                    if localToday > 0 {
                        byDate[todayStr] = localToday
                    }

                    let raw = byDate.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
                    UserDefaults.standard.set(raw, forKey: UDKey.historyRaw)
                    self.rebuildHistory(from: raw)

                    // profileToday : NE PAS backfill depuis le backend pour aujourd'hui
                    // car les données pourraient venir d'un autre appareil.
                    // Seules les sources locales (DAR, Monitor) sont fiables pour "today".
                    // Le local est déjà dans self.profileToday via loadProfileCache().

                    // categorySocial : idem, pas de backfill backend pour aujourd'hui
                    // (le social vient exclusivement du DAR CategoriesScene)

                    // weekAvg et monthAvg : les DARs Apple sont prioritaires
                    // Backfill depuis le backend UNIQUEMENT si les DARs n'ont pas fourni de valeur
                    // (= tel 2 où les extensions ne tournent pas)
                    if self.profileWeekAvg == 0 {
                        let recentDates = byDate.keys.sorted().suffix(7)
                        let weekVals = recentDates.compactMap { byDate[$0] }.filter { $0 > 0 }
                        if !weekVals.isEmpty {
                            let avg = weekVals.reduce(0, +) / weekVals.count
                            self.profileWeekAvg = avg
                            UserDefaults.standard.set(avg, forKey: UDKey.weekAvg)
                        }
                    }
                    if self.profileMonthAvg == 0 {
                        let allDates = byDate.keys.sorted().suffix(30)
                        let monthVals = allDates.compactMap { byDate[$0] }.filter { $0 > 0 }
                        if !monthVals.isEmpty {
                            let avg = monthVals.reduce(0, +) / monthVals.count
                            self.profileMonthAvg = avg
                            UserDefaults.standard.set(avg, forKey: UDKey.monthAvg)
                        }
                    }
                }
            }

            await MainActor.run {
                self.memberStreaks = streaks
                self.memberLastSync = lastSyncByMember
                self.currentStreak = streaks[uid] ?? 0
                appState.objectWillChange.send()
            }
        }
    }

    // MARK: - Push vers le backend

    func syncToBackend(appState: AppState? = nil) {
        let now = Date()
        guard now.timeIntervalSince(lastSyncDate) > 5 else { return }
        lastSyncDate = now
        syncTask?.cancel()
        syncTask = Task {
            await MainActor.run { loadProfileCache() }
            if let appState { await MainActor.run { updateLocalGroups(appState: appState) } }
            let minutes = await MainActor.run { profileToday }
            guard minutes > 0 else { return }
            guard AuthManager.shared.currentUser != nil else { return }
            let social = await MainActor.run { categorySocial }
            // Today's value comes from DAR and is authoritative — use correctScore
            // (direct-assign) so it can overwrite any previously-stored inflated
            // value. Historical days still go through syncScore (GREATEST) below.
            let date = Self.dateFormatter.string(from: Date())
            // Envoyer social seulement si on a une valeur (sinon on écraserait le backend avec nil)
            try? await APIClient.shared.correctScore(minutes: minutes, socialMinutes: social > 0 ? social : nil, date: date)
        }
    }

}
