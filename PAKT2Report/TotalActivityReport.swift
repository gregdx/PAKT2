import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct TotalActivityReport: DeviceActivityReportExtension {
    // Minimal body — 2 scenes only to stay under iOS's 5MB Jetsam limit.
    // Previously had 8 scenes which caused eviction on TestFlight.
    // WeekChartScene is NOT registered because no host view currently uses
    // DeviceActivityReport(.init(rawValue: "weekChart")) — registering a scene
    // that is never rendered just wastes memory.
    var body: some DeviceActivityReportScene {
        // Only 2 scenes to stay under iOS's 5MB Jetsam limit.
        // TodayScene now serves as the full profile scene (today + apps + 14d chart)
        // when the host passes a 14-day filter.
        TodayScene { info in TodayReportView(info: info) }
        CompactScene { info in CompactReportView(info: info) }
    }
}

// MARK: - Shared helpers

private let appGroupID = "group.com.PAKT2"

private let dateFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
}()
private let dayFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US"); return f
}()
private let green = Color(red: 0.00, green: 0.75, blue: 0.36)
private let red   = Color(red: 0.93, green: 0.18, blue: 0.09)

/// Écrit un token dans l'App Group pour valider les URL schemes
private func writeURLToken(_ token: String) {
    UserDefaults(suiteName: appGroupID)?.set(token, forKey: "url_token")
}

private func generateToken() -> String {
    UUID().uuidString
}

/// Construit une URL sécurisée avec token App Group
private func secureURL(_ base: String) -> URL? {
    let token = generateToken()
    writeURLToken(token)
    let separator = base.contains("?") ? "&" : "?"
    return URL(string: "\(base)\(separator)t=\(token)")
}

private func formatST(_ m: Int) -> String {
    "\(m / 60)h\(String(format: "%02d", m % 60))"
}

// MARK: - Keychain sharing (fonctionne même quand App Group est cassé)

// Keep in sync with AppConfig in SharedComponents2.swift
private let keychainGroup = "9U5UZW39LQ.com.PAKT2"

private func keychainWrite(key: String, value: String) {
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

private func writeToShared(key: String, value: Int) {
    // App Group UD
    let ud = UserDefaults(suiteName: appGroupID)
    ud?.set(value, forKey: key)
    ud?.set(dateFmt.string(from: Date()), forKey: "\(key)_date")
    ud?.synchronize()
    // Keychain
    keychainWrite(key: key, value: "\(value)")
    keychainWrite(key: "\(key)_date", value: dateFmt.string(from: Date()))
}

private func writeHistoryToShared(_ raw: String) {
    let ud = UserDefaults(suiteName: appGroupID)
    ud?.set(raw, forKey: "shared_history")
    ud?.synchronize()
    keychainWrite(key: "shared_history", value: raw)
}


/// Poste une Darwin notification pour réveiller l'app principale immédiatement
private func notifyMainApp() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName("com.PAKT2.screenTimeUpdate" as CFString), nil, nil, true)
}

private func goalMinutes() -> Int {
    // Try keychain first, fallback to 180
    if let raw = keychainRead("pakt_socialGoal"), let v = Int(raw), v > 0 { return v }
    return 180
}

// MARK: - Go Backend REST API (direct write from extension)

private let backendBaseURL = "https://pakt-api.fly.dev/v1"

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

private func syncToBackendREST(minutes: Int? = nil, socialMinutes: Int? = nil) {
    let dateStr = dateFmt.string(from: Date())
    var body: [String: Any] = ["date": dateStr]
    if let m = minutes { body["minutes"] = m }
    if let s = socialMinutes { body["social_minutes"] = s }
    guard let url = URL(string: "\(backendBaseURL)/scores/sync"),
          let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = keychainRead("pakt_extension_token") {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = jsonData
    URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
}

private func extractMinutes(from data: DeviceActivityResults<DeviceActivityData>) async -> Int {
    let result = await extractDiagnostics(from: data)
    return result.minutes
}

/// Returns minutes (as max-of-items) + diagnostic counts. `DeviceActivityResults`
/// sometimes yields multiple `DeviceActivityData` blobs for the same day
/// (2026-04-10 observed: items=2 with ~528 + ~45 summing to an overcount).
/// We take the max of per-item totals so noise/duplicate items don't inflate.
private func extractDiagnostics(from data: DeviceActivityResults<DeviceActivityData>) async -> (minutes: Int, items: Int, segments: Int, maxSegMin: Int, perItemMinutes: [Int]) {
    var items = 0
    var totalSegments = 0
    var maxSeg: TimeInterval = 0
    var perItemMinutes: [Int] = []
    for await d in data {
        items += 1
        var itemTotal: TimeInterval = 0
        for await s in d.activitySegments {
            totalSegments += 1
            itemTotal += s.totalActivityDuration
            if s.totalActivityDuration > maxSeg { maxSeg = s.totalActivityDuration }
        }
        perItemMinutes.append(Int(itemTotal / 60))
    }
    let best = perItemMinutes.max() ?? 0
    return (best, items, totalSegments, Int(maxSeg / 60), perItemMinutes)
}

// MARK: - Scene 1 : Today (grand affichage profil)

struct TodayInfo {
    let minutes: Int
    let goal: Int
    let debugItems: Int
    let debugSegments: Int
    let debugMaxSegMin: Int
    let debugPerItem: [Int]
    var apps: [AppUsageRow] = []
    var days: [DayData] = []
    var socialMinutes: Int = 0
    var weekAvg: Int = 0
    var monthAvg: Int = 0
}

struct TodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "todayTotal")
    let content: (TodayInfo) -> TodayReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayInfo {
        let cal = Calendar.current
        let todayStr = dateFmt.string(from: Date())
        let socialKW: Set<String> = ["instagram","tiktok","snapchat","twitter","facebook",
            "messenger","whatsapp","telegram","discord","reddit","threads",
            "linkedin","bereal","signal","youtube","pinterest"]

        var appMap: [String: (minutes: Int, token: ApplicationToken?)] = [:]
        var dayTotals: [String: Int] = [:]
        var todayMinutes = 0
        var socialMinutes = 0

        for await d in data {
            for await seg in d.activitySegments {
                let segDay = dateFmt.string(from: seg.dateInterval.start)
                let segMins = Int(seg.totalActivityDuration / 60)
                dayTotals[segDay, default: 0] += segMins
                guard segDay == todayStr else { continue }
                todayMinutes += segMins
                for await cat in seg.categories {
                    for await app in cat.applications {
                        let m = Int(app.totalActivityDuration / 60)
                        guard m > 0 else { continue }
                        let name = app.application.localizedDisplayName ?? "?"
                        let bundle = (app.application.bundleIdentifier ?? "").lowercased()
                        appMap[name] = (
                            minutes: (appMap[name]?.minutes ?? 0) + m,
                            token: app.application.token
                        )
                        if socialKW.contains(where: { name.lowercased().contains($0) || bundle.contains($0) }) {
                            socialMinutes += m
                        }
                    }
                }
            }
        }

        // Keep the top 10 apps — matches MAX_TRACKED_APPS on the host so the
        // full list can be auto-picked for DAM per-app tracking in one shot.
        let apps = appMap.sorted { $0.value.minutes > $1.value.minutes }
            .prefix(10)
            .map { AppUsageRow(name: $0.key, minutes: $0.value.minutes, token: $0.value.token) }

        var days: [DayData] = []
        for i in (0..<7).reversed() {
            let date = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let key = dateFmt.string(from: date)
            days.append(DayData(label: dayFmt.string(from: date), date: key, minutes: dayTotals[key] ?? 0))
        }
        let nonZero = days.map(\.minutes).filter { $0 > 0 }
        let weekAvg = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / nonZero.count

        return TodayInfo(
            minutes: todayMinutes, goal: goalMinutes(),
            debugItems: 0, debugSegments: 0, debugMaxSegMin: 0, debugPerItem: [],
            apps: apps, days: days, socialMinutes: socialMinutes, weekAvg: weekAvg
        )
    }
}

struct TodayReportView: View {
    let info: TodayInfo

    var body: some View {
        // "TON POISON" — just the 3 most-used app icons, no numbers.
        VStack(spacing: 14) {
            HStack(spacing: 20) {
                ForEach(info.apps.prefix(3)) { app in
                    if let token = app.token {
                        Label(token).labelStyle(.iconOnly)
                            .frame(width: 56, height: 56)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 56, height: 56)
                    }
                }
            }

            Text("TON POISON")
                .font(.system(size: 12, weight: .heavy))
                .tracking(3)
                .foregroundColor(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .preference(key: TodayMinutesKey.self, value: info.minutes)
    }
}

// MARK: - Scene 2 : Compact (pour les groupes)

struct CompactScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "compact")
    let content: (TodayInfo) -> CompactReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayInfo {
        let minutes = await extractMinutes(from: data)
        return TodayInfo(minutes: minutes, goal: goalMinutes(), debugItems: 0, debugSegments: 0, debugMaxSegMin: 0, debugPerItem: [])
    }
}

struct CompactReportView: View {
    let info: TodayInfo
    var over: Bool { info.minutes > info.goal }
    // openURL removed — crashes on iOS 17 view services

    var body: some View {
        Text(info.minutes > 0 ? formatST(info.minutes) : "--")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(over ? red : Color.primary)
    }
}

// MARK: - Scene 2b : Compact Week Avg (pour classement groupe)

struct CompactWeekScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "compactWeek")
    let content: (TodayInfo) -> CompactReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayInfo {
        let daily = await minutesPerDay(from: data)
        let withData = daily.values.filter { $0 > 0 }
        let avg = withData.isEmpty ? 0 : withData.reduce(0, +) / withData.count
        return TodayInfo(minutes: avg, goal: goalMinutes(), debugItems: 0, debugSegments: 0, debugMaxSegMin: 0, debugPerItem: [])
    }
}

// MARK: - Scene 2c : Compact Month Avg (pour classement groupe)

struct CompactMonthScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "compactMonth")
    let content: (TodayInfo) -> CompactReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayInfo {
        let daily = await minutesPerDay(from: data)
        let withData = daily.values.filter { $0 > 0 }
        let avg = withData.isEmpty ? 0 : withData.reduce(0, +) / withData.count
        return TodayInfo(minutes: avg, goal: goalMinutes(), debugItems: 0, debugSegments: 0, debugMaxSegMin: 0, debugPerItem: [])
    }
}

// MARK: - Scene 3 : Week Average

struct WeekAvgScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "weekAverage")
    let content: (Int) -> AvgReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        let daily = await minutesPerDay(from: data)
        let sevenDaysAgo = dateFmt.string(from: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        let weekData = daily.filter { $0.key >= sevenDaysAgo && $0.value > 0 }
        let avg = weekData.isEmpty ? 0 : weekData.values.reduce(0, +) / weekData.count
        if avg > 0 {
            writeToShared(key: "shared_weekavg", value: avg)
            notifyMainApp()
        }
        return avg
    }
}

// MARK: - Scene 4 : Month Average

struct MonthAvgScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "monthAverage")
    let content: (Int) -> AvgReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        let daily = await minutesPerDay(from: data)
        let withData = daily.values.filter { $0 > 0 }
        let avg = withData.isEmpty ? 0 : withData.reduce(0, +) / withData.count
        if avg > 0 {
            writeToShared(key: "shared_monthavg", value: avg)
            notifyMainApp()
        }
        return avg
    }
}

struct AvgReportView: View {
    let minutes: Int
    let label: String
    @Environment(\.openURL) private var openURL
    private var isWeek: Bool { label.contains("week") }

    var body: some View {
        VStack(spacing: 2) {
            Text(minutes > 0 ? formatST(minutes) : "--")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color.primary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.secondary.opacity(0.5))
                .tracking(0.8)
        }
        .preference(key: WeekAvgKey.self, value: isWeek ? minutes : 0)
        .preference(key: MonthAvgKey.self, value: isWeek ? 0 : minutes)
        .onAppear {
            guard minutes > 0 else { return }
            let type = isWeek ? "weekavg" : "monthavg"
            let sharedKey = isWeek ? "shared_weekavg" : "shared_monthavg"
            writeToShared(key: sharedKey, value: minutes)
            if let url = URL(string: "pakt2://\(type)?minutes=\(minutes)") { openURL(url) }
        }
    }
}

// MARK: - Scene 5 : Week Chart

struct DayData: Identifiable {
    let id = UUID()
    let label: String
    let date: String  // "yyyy-MM-dd"
    let minutes: Int
}

func minutesPerDay(from data: DeviceActivityResults<DeviceActivityData>) async -> [String: Int] {
    var result: [String: Int] = [:]
    for await d in data {
        for await seg in d.activitySegments {
            // Use segment-level duration only (matches Apple Settings).
            // See extractMinutes for the rationale on dropping category max().
            let m = Int(seg.totalActivityDuration / 60)
            let key = dateFmt.string(from: seg.dateInterval.start)
            result[key, default: 0] += m
        }
    }
    return result
}

struct WeekChartScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "weekChart")
    let content: ([DayData]) -> ChartReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [DayData] {
        let cal = Calendar.current
        let minutesByDate = await minutesPerDay(from: data)

        var result: [DayData] = []
        for i in (0..<7).reversed() {
            let date = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let dateKey = dateFmt.string(from: date)
            result.append(DayData(label: dayFmt.string(from: date), date: dateKey, minutes: minutesByDate[dateKey] ?? 0))
        }

        let entries = result.filter { $0.minutes > 0 }.map { "\($0.date):\($0.minutes)" }
        let param = entries.joined(separator: ",")

        if !entries.isEmpty {
            writeHistoryToShared(param)
            notifyMainApp()
        }

        return result
    }
}

struct ChartReportView: View {
    let data: [DayData]
    var goal: Int { goalMinutes() }
    var maxM: Int { max(data.map { $0.minutes }.max() ?? 1, goal, 1) }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data) { day in
                    VStack(spacing: 4) {
                        if day.minutes > 0 {
                            Text(formatST(day.minutes))
                                .font(.system(size: 8))
                                .foregroundColor(day.minutes > goal ? red : Color.secondary)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.minutes > goal ? red.opacity(0.8) : (day.minutes > 0 ? green.opacity(0.7) : Color.gray.opacity(0.2)))
                            .frame(height: max(4, CGFloat(day.minutes) / CGFloat(maxM) * 120))
                        Text(day.label)
                            .font(.system(size: 9))
                            .foregroundColor(Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 160)

            HStack(spacing: 4) {
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 0.5)
                Text("goal \(formatST(goal))")
                    .font(.system(size: 8))
                    .foregroundColor(Color.secondary.opacity(0.5))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .preference(key: HistoryKey.self, value: data.filter { $0.minutes > 0 }.map { "\($0.date):\($0.minutes)" }.joined(separator: ","))
        .onAppear {
            let entries = data.filter { $0.minutes > 0 }.map { "\($0.date):\($0.minutes)" }
            guard !entries.isEmpty else { return }
            let param = entries.joined(separator: ",")
            writeHistoryToShared(param)
            if let url = URL(string: "pakt2://history?d=\(param)") { openURL(url) }
        }
    }
}

// MARK: - Scene 6 : Social + per-app time breakdown

struct CategoriesScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "categories")
    let content: (Int) -> CategoriesReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        let socialKW: Set<String> = ["instagram","tiktok","snapchat","twitter","facebook","messenger",
                        "whatsapp","telegram","discord","reddit","threads","linkedin",
                        "bereal","signal","wechat","pinterest","mastodon","youtube"]

        let todayStart = Calendar.current.startOfDay(for: Date())
        var socialMinutes = 0

        for await d in data {
            for await segment in d.activitySegments {
                guard segment.dateInterval.start >= todayStart else { continue }
                for await catActivity in segment.categories {
                    let catMinutes = Int(catActivity.totalActivityDuration / 60)
                    guard catMinutes > 0 else { continue }

                    var isSocial = false
                    for await a in catActivity.applications {
                        guard !isSocial else { continue }
                        let name = (a.application.localizedDisplayName ?? "").lowercased()
                        let bundle = (a.application.bundleIdentifier ?? "").lowercased()
                        isSocial = socialKW.contains { name.contains($0) || bundle.contains($0) }
                    }
                    if isSocial { socialMinutes += catMinutes }
                }
            }
        }

        if socialMinutes > 0 {
            writeToShared(key: "shared_social", value: socialMinutes)
            syncToBackendREST(socialMinutes: socialMinutes)
            notifyMainApp()
        }
        return socialMinutes
    }
}

// MARK: - Shared types for TodayScene full profile rendering

struct AppUsageRow: Identifiable {
    let id = UUID()
    let name: String
    let minutes: Int
    let token: ApplicationToken?
}

// FullProfileScene removed — folded into TodayScene to stay under Jetsam limit.

struct CategoriesReportView: View {
    let data: Int
    var socialGoal: Int {
        let ag = UserDefaults(suiteName: appGroupID)?.integer(forKey: "socialGoalMinutes") ?? 0
        if ag > 0 { return ag }
        if let raw = keychainRead("pakt_socialGoal"), let v = Int(raw), v > 0 { return v }
        return 120
    }
    var over: Bool { data > socialGoal && socialGoal > 0 }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 4) {
            Text(data > 0 ? formatST(data) : "--")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(data == 0 ? Color.primary : (over ? red : green))
            Text("ON SOCIAL MEDIA")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.secondary.opacity(0.5))
                .tracking(0.8)
        }
        .preference(key: SocialMinutesKey.self, value: data)
        .onAppear {
            guard data > 0 else { return }
            writeToShared(key: "shared_social", value: data)
            syncToBackendREST(socialMinutes: data)
            if let url = URL(string: "pakt2://categories?social=\(data)") { openURL(url) }
        }
    }
}
