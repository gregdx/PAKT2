import DeviceActivity
import ExtensionKit
import ManagedSettings
import SwiftUI

@main
struct TotalActivityReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayScene { info in TodayReportView(info: info) }
        CompactScene { info in CompactReportView(info: info) }
        CompactWeekScene { info in CompactReportView(info: info) }
        CompactMonthScene { info in CompactReportView(info: info) }
        WeekChartScene { data in ChartReportView(data: data) }
        WeekAvgScene { avg in AvgReportView(minutes: avg, label: "week avg") }
        MonthAvgScene { avg in AvgReportView(minutes: avg, label: "month avg") }
        CategoriesScene { data in CategoriesReportView(data: data) }
    }
}

// MARK: - Shared helpers

private let appGroupID = "group.com.PAKT2"
private let green = Color(red: 0.00, green: 0.75, blue: 0.36)
private let red   = Color(red: 0.93, green: 0.18, blue: 0.09)

/// Écrit un token dans l'App Group pour valider les URL schemes
private func writeURLToken(_ token: String) {
    UserDefaults(suiteName: appGroupID)?.set(token, forKey: "url_token")
}

private func generateToken() -> String {
    let ts = Int(Date().timeIntervalSince1970)
    return "\(ts)"
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

private let keychainGroup = "9U5UZW39LQ.com.PAKT2"

private func keychainWrite(key: String, value: String) {
    let data = value.data(using: .utf8)!
    // Supprimer l'ancien item SANS access group (migration)
    let oldQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key
    ]
    SecItemDelete(oldQuery as CFDictionary)
    // Supprimer aussi avec access group
    let groupQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecAttrAccessGroup as String: keychainGroup
    ]
    SecItemDelete(groupQuery as CFDictionary)
    // Ajouter avec access group explicite
    var add = groupQuery
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    add[kSecValueData as String] = data
    SecItemAdd(add as CFDictionary, nil)
}

private func writeToShared(key: String, value: Int) {
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
    // App Group UD
    let ud = UserDefaults(suiteName: appGroupID)
    ud?.set(value, forKey: key)
    ud?.set(df.string(from: Date()), forKey: "\(key)_date")
    ud?.synchronize()
    // Keychain
    keychainWrite(key: key, value: "\(value)")
    keychainWrite(key: "\(key)_date", value: df.string(from: Date()))
}

private func writeHistoryToShared(_ raw: String) {
    let ud = UserDefaults(suiteName: appGroupID)
    ud?.set(raw, forKey: "shared_history")
    ud?.synchronize()
    keychainWrite(key: "shared_history", value: raw)
}

private func goalMinutes() -> Int {
    // Try keychain first, fallback to 180
    if let raw = keychainRead("pakt_socialGoal"), let v = Int(raw), v > 0 { return v }
    return 180
}

private func writeToAppGroup(minutes: Int) -> String {
    guard minutes > 0 else { return "skip:0min" }
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
    ) else { return "skip:noContainer" }
    let fileURL = containerURL.appendingPathComponent("report.json")
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
    let payload: [String: Any] = ["minutes": minutes, "date": df.string(from: Date())]
    do {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: fileURL, options: .atomic)
        return "wrote:\(minutes)"
    } catch {
        return "err:\(error.localizedDescription.prefix(30))"
    }
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
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
    let dateStr = df.string(from: Date())
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

// MARK: - Pending score (disabled — UIKit crashes on iOS 17 view services)

private func syncPendingScore(minutes: Int? = nil, socialMinutes: Int? = nil) {
    // Disabled: UIDevice not available in DeviceActivityReport view service on iOS 17
}

private func extractMinutes(from data: DeviceActivityResults<DeviceActivityData>) async -> Int {
    var total: TimeInterval = 0
    var segmentCount = 0
    var dataCount = 0
    for await d in data {
        dataCount += 1
        for await s in d.activitySegments {
            total += s.totalActivityDuration
            segmentCount += 1
            print("[PAKT Report] segment: \(Int(s.totalActivityDuration/60))min interval=\(s.dateInterval)")
        }
    }
    let minutes = Int(total / 60)
    print("[PAKT Report] extractMinutes: \(minutes) min from \(segmentCount) segments, \(dataCount) data entries")
    return minutes
}

// MARK: - Scene 1 : Today (grand affichage profil)

struct TodayInfo {
    let minutes: Int
    let goal: Int
}

struct TodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "todayTotal")
    let content: (TodayInfo) -> TodayReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayInfo {
        let minutes = await extractMinutes(from: data)
        _ = writeToAppGroup(minutes: minutes)
        if minutes > 0 {
            writeToShared(key: "shared_today", value: minutes)
            syncToBackendREST(minutes: minutes)
        }
        return TodayInfo(minutes: minutes, goal: goalMinutes())
    }
}

struct TodayReportView: View {
    let info: TodayInfo
    var over: Bool { info.minutes > info.goal }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 4) {
            Text(info.minutes > 0 ? formatST(info.minutes) : "--")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(info.minutes == 0 ? Color.primary : (over ? red : green))
            Text("TODAY")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.secondary.opacity(0.5))
                .tracking(1.0)
        }
        .preference(key: TodayMinutesKey.self, value: info.minutes)
        .onAppear {
            guard info.minutes > 0 else { return }
            writeToShared(key: "shared_today", value: info.minutes)
            syncToBackendREST(minutes: info.minutes)
            if let url = URL(string: "pakt2://screentime?minutes=\(info.minutes)") {
                openURL(url)
            }
        }
    }
}

// MARK: - Scene 2 : Compact (pour les groupes)

struct CompactScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "compact")
    let content: (TodayInfo) -> CompactReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayInfo {
        let minutes = await extractMinutes(from: data)
        writeToAppGroup(minutes: minutes)
        return TodayInfo(minutes: minutes, goal: goalMinutes())
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
        return TodayInfo(minutes: avg, goal: goalMinutes())
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
        return TodayInfo(minutes: avg, goal: goalMinutes())
    }
}

// MARK: - Scene 3 : Week Average

struct WeekAvgScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "weekAverage")
    let content: (Int) -> AvgReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        let daily = await minutesPerDay(from: data)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let sevenDaysAgo = df.string(from: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        let weekData = daily.filter { $0.key >= sevenDaysAgo && $0.value > 0 }
        let avg = weekData.isEmpty ? 0 : weekData.values.reduce(0, +) / weekData.count
        print("[PAKT WeekAvgScene] days=\(daily.count) weekDays=\(weekData.count) avg=\(avg)")
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
        print("[PAKT MonthAvgScene] days=\(daily.count) withData=\(withData.count) avg=\(avg)")
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
    let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
    var result: [String: Int] = [:]
    for await d in data {
        for await seg in d.activitySegments {
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
        let df = DateFormatter(); df.dateFormat = "EEE"; df.locale = Locale(identifier: "en_US")
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current

        var minutesByDate: [String: Int] = [:]
        for await d in data {
            for await seg in d.activitySegments {
                let m = Int(seg.totalActivityDuration / 60)
                let dateKey = dateFmt.string(from: seg.dateInterval.start)
                minutesByDate[dateKey, default: 0] += m
            }
        }

        print("[PAKT WeekChart] minutesByDate=\(minutesByDate)")

        var result: [DayData] = []
        for i in (0..<7).reversed() {
            let date = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let dateKey = dateFmt.string(from: date)
            result.append(DayData(label: df.string(from: date), date: dateKey, minutes: minutesByDate[dateKey] ?? 0))
        }

        let entries = result.filter { $0.minutes > 0 }.map { "\($0.date):\($0.minutes)" }
        let param = entries.joined(separator: ",")

        if !entries.isEmpty {
            writeHistoryToShared(param)
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
        let socialKW = ["instagram","tiktok","snapchat","twitter","facebook","messenger",
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
                        let name = (a.application.localizedDisplayName ?? "").lowercased()
                        let bundle = (a.application.bundleIdentifier ?? "").lowercased()
                        if !isSocial {
                            for kw in socialKW where name.contains(kw) || bundle.contains(kw) {
                                isSocial = true
                                break
                            }
                        }
                    }
                    if isSocial { socialMinutes += catMinutes }
                }
            }
        }

        print("[PAKT CategoriesScene] social=\(socialMinutes)")
        if socialMinutes > 0 {
            writeToShared(key: "shared_social", value: socialMinutes)
            syncToBackendREST(socialMinutes: socialMinutes)
        }
        return socialMinutes
    }
}

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
