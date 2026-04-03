import SwiftUI
import Combine
import FamilyControls
import DeviceActivity
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
    @Published var profileWeekAvg: Int = 0
    @Published var profileMonthAvg: Int = 0
    @Published var profileHistory: [ProfileDayData] = []
    @Published var categorySocial: Int = 0
    @Published var trackedAppMinutes: Int = 0  // Per-app tracking total for scope=.apps groups
    @Published var currentStreak: Int = 0
    @Published var memberStreaks: [String: Int] = [:]
    @Published var memberLastSync: [String: Date] = [:]
    static let streakGoalMinutes = 180

    private var syncTask: Task<Void, Never>?
    private var fetchCumulativeTask: Task<Void, Never>?
    private var lastSyncDate: Date = .distantPast
    var lastFetchDate: Date = .distantPast

    init() {
        isAuthorized = center.authorizationStatus == .approved
        loadProfileCache()
        registerDarwinNotification()
    }

    /// Écoute les Darwin notifications postées par les extensions DAR/Monitor
    /// pour relire immédiatement les données du App Group / Keychain
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
                    Log.d("[PAKT] Darwin notification received — reloading profile cache")
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
        let today = Self.dateFormatter.string(from: Date())
        var todaySource = "none"
        var socialSource = "none"
        var weekSource = "none"
        var monthSource = "none"

        // === 1. Cache standard (alimenté par openURL / preference keys) ===

        if UserDefaults.standard.string(forKey: UDKey.todayDate) == today {
            profileToday = UserDefaults.standard.integer(forKey: UDKey.todayMinutes)
            if profileToday > 0 { todaySource = "ud_standard" }
        } else {
            profileToday = 0
        }

        if UserDefaults.standard.string(forKey: UDKey.catSocialDate) == today {
            categorySocial = UserDefaults.standard.integer(forKey: UDKey.catSocial)
            if categorySocial > 0 { socialSource = "ud_standard" }
        } else {
            categorySocial = 0
        }

        profileWeekAvg = UserDefaults.standard.integer(forKey: UDKey.weekAvg)
        profileMonthAvg = UserDefaults.standard.integer(forKey: UDKey.monthAvg)
        if profileWeekAvg > 0 { weekSource = "ud_standard" }
        if profileMonthAvg > 0 { monthSource = "ud_standard" }

        // === 2. Fallback: App Group UD (écrit par les extensions DAR/Monitor) ===

        if profileToday == 0 {
            let v = sharedUD?.integer(forKey: "shared_today") ?? 0
            let d = sharedUD?.string(forKey: "shared_today_date") ?? ""
            if v > 0 && d == today { profileToday = v; todaySource = "app_group" }
        }
        if categorySocial == 0 {
            let v = sharedUD?.integer(forKey: "shared_social") ?? 0
            let d = sharedUD?.string(forKey: "shared_social_date") ?? ""
            if v > 0 && d == today { categorySocial = v; socialSource = "app_group" }
        }
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
            if v > 0 && d == today { profileToday = v; todaySource = "keychain" }
        }
        if categorySocial == 0 {
            let v = keychainInt("shared_social")
            let d = keychainRead("shared_social_date") ?? ""
            if v > 0 && d == today { categorySocial = v; socialSource = "keychain" }
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
        Log.d("[PAKT loadProfileCache] today=\(profileToday)(\(todaySource)) social=\(categorySocial)(\(socialSource)) weekAvg=\(profileWeekAvg)(\(weekSource)) monthAvg=\(profileMonthAvg)(\(monthSource)) | DAR=\(darDebug)")

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

        // History — fusionner toutes les sources pour ne pas rester bloqué sur un cache périmé
        let stdRaw = UserDefaults.standard.string(forKey: UDKey.historyRaw) ?? ""
        let sharedRaw = sharedUD?.string(forKey: "shared_history") ?? ""
        let kcRaw = keychainRead("shared_history") ?? ""
        let mergedHistory = mergeHistoryRaw([stdRaw, sharedRaw, kcRaw])
        if !mergedHistory.isEmpty {
            UserDefaults.standard.set(mergedHistory, forKey: UDKey.historyRaw)
            rebuildHistory(from: mergedHistory)
        } else {
            buildEmptyHistory()
        }
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
        buildHistoryFromMap(parseHistoryCSV(raw))
    }

    private func buildEmptyHistory() { buildHistoryFromMap([:]) }

    private func buildHistoryFromMap(_ byDate: [String: Int]) {
        var merged = byDate
        // Toujours injecter profileToday pour que le jour courant soit à jour
        // même si le weekChart scene n'a pas renvoyé de données fraîches
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

    func startBackgroundMonitoring() {
        guard isAuthorized else { return }
        let center = DeviceActivityCenter()

        // Schedule: monitor from midnight to midnight, repeating daily
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        // Create threshold events every 15 minutes of total device usage (15, 30, 45, ..., 720)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for mins in stride(from: 15, through: 720, by: 15) {
            let eventName = DeviceActivityEvent.Name("threshold_\(mins)")
            events[eventName] = DeviceActivityEvent(
                threshold: DateComponents(minute: mins)
            )
        }

        do {
            try center.startMonitoring(
                .init("daily_screentime"),
                during: schedule,
                events: events
            )
            Log.d("[PAKT Monitor] Background monitoring started with \(events.count) thresholds")
        } catch {
            Log.d("[PAKT Monitor] Failed to start monitoring: \(error)")
        }
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
        let today = profileToday
        let social = categorySocial
        let uid = appState.currentUID
        guard !uid.isEmpty, !appState.groups.isEmpty else { return }

        var didChange = false
        for gi in appState.groups.indices {
            for mi in appState.groups[gi].members.indices {
                if appState.groups[gi].members[mi].uid == uid {
                    // todayMinutes : le local (DAR/Monitor) est autoritaire
                    // Écrire même si la valeur locale est plus basse (corrige les données fausses du backend)
                    if today > 0 && appState.groups[gi].members[mi].todayMinutes != today {
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
                    if lastSyncByMember[s.userId] == nil || s.submittedAt > lastSyncByMember[s.userId]! {
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
                    let isMe = update.memberUid == uid
                    if isMe {
                        // Pour moi : le local est autoritaire, écriture directe
                        appState.groups[gi].members[mi].todayMinutes = update.todayMinutes
                        appState.groups[gi].members[mi].todaySocialMinutes = update.todaySocialMinutes
                    } else {
                        // Pour les autres : max() pour ne pas régresser les updates WebSocket
                        appState.groups[gi].members[mi].todayMinutes = max(appState.groups[gi].members[mi].todayMinutes, update.todayMinutes)
                        appState.groups[gi].members[mi].todaySocialMinutes = max(appState.groups[gi].members[mi].todaySocialMinutes, update.todaySocialMinutes)
                    }
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
            let date = Self.dateFormatter.string(from: Date())
            // Envoyer social seulement si on a une valeur (sinon on écraserait le backend avec nil)
            try? await APIClient.shared.syncScore(minutes: minutes, socialMinutes: social > 0 ? social : nil, date: date)
        }
    }

}
