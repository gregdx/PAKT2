import SwiftUI

struct MemberProfileView: View {
    let member : Member
    let rank   : Int
    let total  : Int
    let group  : Group
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fm = FriendManager.shared
    @ObservedObject private var stManager = ScreenTimeManager.shared
    @State private var weekHistory: [DataPoint] = []
    @State private var memberAchievements: Set<String> = []

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d/M"; f.locale = Locale(identifier: "en_US"); return f
    }()

    var color: Color { memberColor(rank: rank, total: total, mode: group.mode) }
    var isSocial: Bool { group.scope == .social }

    /// Minutes selon le scope du groupe
    var todayMins: Int { isSocial ? member.todaySocialMinutes : member.todayMinutes }
    var wakingPct: Int { Int((Double(todayMins) / kWakingMinutesPerDay) * 100) }

    /// Cumul total (inclut aujourd'hui via le listener)
    var sinceStartTotal: Int { isSocial ? member.monthSocialMinutes : member.monthMinutes }
    /// Cumul hors aujourd'hui
    var sinceStartPast: Int { max(0, sinceStartTotal - todayMins) }
    /// Nombre de jours passés (hors aujourd'hui)
    var pastDays: Int {
        let start = Calendar.current.startOfDay(for: group.startDate)
        let today = Calendar.current.startOfDay(for: Date())
        return max(1, Calendar.current.dateComponents([.day], from: start, to: today).day ?? 1)
    }
    /// Moyenne quotidienne
    var sinceStartDailyAvg: Int { sinceStartPast / pastDays }
    var sinceStartWakingPct: Int { Int((Double(sinceStartDailyAvg) / kWakingMinutesPerDay) * 100) }
    var daysPerYear: Int { Int(Double(todayMins) * 365.0 / 1440.0) }

    var goalReached: Bool {
        todayMins > 0 && todayMins <= group.goalMinutes
    }
    var sinceStartGoalReached: Bool {
        sinceStartDailyAvg > 0 && sinceStartDailyAvg <= group.goalMinutes
    }
    var numberColor: Color { Theme.text }

    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    bigNumber
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24).padding(.top, 24)
                    quickStats.padding(.horizontal, 24).padding(.top, 24)
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24).padding(.top, 24)
                    objectiveSection.padding(.horizontal, 24).padding(.top, 24)
                    Spacer().frame(height: 80)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
        .navigationBarHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
        .task {
            if let profile = try? await APIClient.shared.getUserProfile(uid: member.uid) {
                await MainActor.run { memberAchievements = Set(profile.achievements) }
            }
        }
    }

    // MARK: - Header

    var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }
                .accessibilityLabel(L10n.t("done"))
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 60)

            AvatarView(name: member.name, size: 72, color: color,
                       uid: member.uid, isMe: appState.isMe(member))
                .environmentObject(appState)

            Text(member.name)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(Theme.text)

            HStack(spacing: 10) {
                Text("#\(rank) in \(group.name)" + (isSocial ? " · " + L10n.t("on_social_media") : ""))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textFaint)
            }

            if stManager.memberStreaks[member.uid] ?? 0 > 0 {
                let memberStreak = stManager.memberStreaks[member.uid] ?? 0
                HStack(spacing: 8) {
                    Text("\u{1F525}")
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(memberStreak) " + L10n.t("day_streak"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.text)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 18)
                .background(Theme.green.opacity(0.08))
                .cornerRadius(20)
                .padding(.bottom, 8)
            }

            if !appState.isMe(member) {
                addFriendButton
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Add friend button

    @ViewBuilder
    var addFriendButton: some View {
        if fm.isFriend(member.uid) {
            Text(L10n.t("friends_check"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.green)
                .padding(.vertical, 8).padding(.horizontal, 18)
                .background(Theme.green.opacity(0.1)).cornerRadius(10)
        } else if fm.outgoingIds.contains(member.uid) {
            Text(L10n.t("request_sent"))
                .font(.system(size: 14))
                .foregroundColor(Theme.textFaint)
                .padding(.vertical, 8).padding(.horizontal, 18)
                .liquidGlass(cornerRadius: 10)
        } else {
            let user = AppUser(id: member.uid, firstName: member.name, email: "")
            Button(action: { fm.sendRequest(to: user) }) {
                Text(L10n.t("add_friend_btn"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .padding(.vertical, 10).padding(.horizontal, 22)
                    .liquidGlass(cornerRadius: 12)
            }
        }
    }

    // MARK: - Big number (today)

    var bigNumber: some View {
        let over = todayMins > group.goalMinutes

        return VStack(spacing: 8) {
            Text(todayMins > 0 ? formatTime(todayMins) : "--")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(todayMins == 0 ? Theme.text : (over ? Theme.red : Theme.green))

            Text(L10n.t("today").uppercased())
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textFaint)
                .tracking(0.8)

            if todayMins > 0 {
                let yearsOnScreens = Double(daysPerYear) * 80.0 / 365.0
                VStack(spacing: 12) {
                    Text("\(daysPerYear) \(L10n.t("days_lost_year"))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                    Text(String(format: "%.1f", yearsOnScreens) + " \(L10n.t("years_in_lifetime"))")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: 12)
                .padding(.top, 12)
                .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Chart

    var chart: some View {
        ChartWithAxes(
            histories:   [weekHistory.map { $0.minutes }],
            colors:      [color],
            goalMinutes: group.goalMinutes,
            xLabels:     weekHistory.map { $0.day },
            names:       [member.name],
            uids:        [member.uid]
        )
        .task {
            await loadWeekHistory()
        }
    }

    private func loadWeekHistory() async {
        let cal = Calendar.current
        let startStr = Self.dateFmt.string(from: cal.startOfDay(for: group.startDate))

        var scoresByDate: [String: Int] = [:]
        do {
            let scores = try await APIClient.shared.getGroupScores(groupID: group.id.uuidString, since: startStr)
            for score in scores where score.userId == member.uid {
                scoresByDate[score.date] = score.minutes
            }
        } catch {
            Log.d("[MemberProfileView] loadWeekHistory error: \(error)")
        }

        // Construire depuis le debut du groupe jusqu'a aujourd'hui
        let startDate = cal.startOfDay(for: group.startDate)
        let today = cal.startOfDay(for: Date())
        let totalDays = max(1, (cal.dateComponents([.day], from: startDate, to: today).day ?? 0) + 1)

        var result: [DataPoint] = []
        for i in 0..<totalDays {
            let date = cal.date(byAdding: .day, value: i, to: startDate) ?? startDate
            let dateKey = Self.dateFmt.string(from: date)
            let label = Self.shortDateFmt.string(from: date)
            let minutes = scoresByDate[dateKey] ?? 0
            result.append(DataPoint(day: label, minutes: minutes))
        }

        await MainActor.run { weekHistory = result }
    }


    // MARK: - Quick stats

    var quickStats: some View {
        VStack(spacing: 4) {
            Text(sinceStartTotal > 0 ? formatTime(sinceStartTotal) : "--")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.text)
            Text(L10n.t("since_start"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textFaint)
                .tracking(0.8)
        }
    }

    // MARK: - Objective

    var objectiveSection: some View {
        let daysWithData = weekHistory.filter { $0.minutes > 0 }
        let daysUnder = daysWithData.filter { $0.minutes <= group.goalMinutes }.count
        let daysOver = daysWithData.count - daysUnder

        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("group_goal"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(1.6)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatTime(group.goalMinutes))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(L10n.t("per_day_max"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(daysUnder)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(L10n.t("days_under"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textFaint)
                }
            }

            if daysOver > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Theme.red).frame(width: 8, height: 8)
                    Text("\(daysOver) " + L10n.t("days_over"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
    }

    // MARK: - Achievements (same layout as ProfileView)

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: L10n.t("medals"))
                Spacer()
                let count = memberAchievements.count
                let total = AchievementDef.all.count
                Text("\(count)/\(total)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(AchievementDef.all) { achievement in
                    let unlocked = memberAchievements.contains(achievement.id)
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(unlocked ? achievement.color.opacity(0.15) : Theme.bgWarm)
                                .frame(width: 44, height: 44)
                            Image(systemName: achievement.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(unlocked ? achievement.color : Theme.textFaint)
                        }
                        Text(achievement.name)
                            .font(.system(size: 12, weight: unlocked ? .semibold : .regular))
                            .foregroundColor(unlocked ? Theme.text : Theme.textFaint)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 30)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .opacity(unlocked ? 1.0 : 0.4)
                }
            }
        }
    }
}
