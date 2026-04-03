import SwiftUI
import PhotosUI
import DeviceActivity

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var stManager = ScreenTimeManager.shared
    @StateObject private var fm = FriendManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isDarkMode") private var isDarkMode = false

    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var showFriends   = false
    @State private var showSettings  = false
    @State private var profileRefreshTimer: Timer? = nil
    @State private var isTimerRunning = false
    @State private var tappedDay: String? = nil
    @State private var myAchievements: Set<String> = []
    @State private var showGroupDetail = false
    @State private var selectedGroupId: UUID? = nil
    var goalMinutes: Int { Int(appState.goalHours * 60) }

    private func startProfileRefresh() {
        guard !isTimerRunning else { return }
        isTimerRunning = true
        ScreenTimeManager.shared.loadProfileCache()
        // Relire toutes les 10 secondes
        profileRefreshTimer?.invalidate()
        profileRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            ScreenTimeManager.shared.loadProfileCache()
        }
    }

    // Filtres : .iPhone uniquement pour ne pas agréger les données d'autres appareils
    private var todayFilter: DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Date())),
            devices: .init([.iPhone])
        )
    }
    private var weekFilter: DeviceActivityFilter {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -14, to: end) ?? end
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: end)),
            devices: .init([.iPhone])
        )
    }
    private var monthFilter: DeviceActivityFilter {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: end)),
            devices: .init([.iPhone])
        )
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    // DARs — 5 scenes séparées (comme avant)
                    VStack(spacing: 0) {
                        DeviceActivityReport(.init(rawValue: "todayTotal"), filter: todayFilter)
                            .frame(maxWidth: .infinity, minHeight: 1)
                        DeviceActivityReport(.init(rawValue: "weekAverage"), filter: weekFilter)
                            .frame(maxWidth: .infinity, minHeight: 1)
                        DeviceActivityReport(.init(rawValue: "monthAverage"), filter: monthFilter)
                            .frame(maxWidth: .infinity, minHeight: 1)
                        DeviceActivityReport(.init(rawValue: "categories"), filter: todayFilter)
                            .frame(maxWidth: .infinity, minHeight: 1)
                        DeviceActivityReport(.init(rawValue: "weekChart"), filter: weekFilter)
                            .frame(maxWidth: .infinity, minHeight: 1)
                    }
                    .frame(height: 5).opacity(0.01)
                    .allowsHitTesting(false)

                    // Stats SwiftUI
                    VStack(spacing: 0) {
                        todayStats
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)

                        streakBadge

                        avgStats

                        weekChart

                        insightCard
                    }

                    // Achievements
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24).padding(.vertical, 24)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionTitle(text: L10n.t("medals"))
                            Spacer()
                            let count = myAchievements.count
                            let total = AchievementDef.all.count
                            Text("\(count)/\(total)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.textFaint)
                                .padding(.trailing, 24)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                            ForEach(AchievementDef.all) { achievement in
                                let unlocked = myAchievements.contains(achievement.id)
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
                        .padding(.horizontal, 24)
                    }

                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24).padding(.vertical, 24)
                    groupsSummary.padding(.horizontal, 24)
                    Spacer().frame(height: 80)
                }
            }
            // DARs are inline in the scroll
        }
        .onAppear { startProfileRefresh() }
        .task {
            if let uid = AuthManager.shared.currentUser?.id {
                if let profile = try? await APIClient.shared.getUserProfile(uid: uid) {
                    await MainActor.run { myAchievements = Set(profile.achievements) }
                }
                // Backfill le graphe avec les scores du backend (force: bypass cooldown)
                ScreenTimeManager.shared.fetchSinceStartCumulative(uid: uid, appState: appState, force: true)
            }
        }
        .onDisappear {
            profileRefreshTimer?.invalidate()
            profileRefreshTimer = nil
            isTimerRunning = false
        }
        .refreshable {
            ScreenTimeManager.shared.loadProfileCache()
            ScreenTimeManager.shared.updateLocalGroups(appState: appState)
            ScreenTimeManager.shared.syncToBackend(appState: appState)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        .onPreferenceChange(TodayMinutesKey.self) { minutes in
            guard minutes > 0 else { return }
            Log.d("[PAKT Profile] TodayMinutes received: \(minutes)")
            let todayStr = ScreenTimeManager.dateFormatter.string(from: Date())
            UserDefaults.standard.set(minutes, forKey: UDKey.todayMinutes)
            UserDefaults.standard.set(todayStr, forKey: UDKey.todayDate)
            stManager.updateProfileToday(minutes)
            stManager.injectTodayIntoHistory(date: todayStr, minutes: minutes)
            // Pousser la valeur réelle au backend (corrige les seuils arrondis du monitor)
            let social = stManager.categorySocial
            Task { try? await APIClient.shared.syncScore(minutes: minutes, socialMinutes: social, date: todayStr) }
        }
        .onPreferenceChange(SocialMinutesKey.self) { social in
            guard social > 0 else { return }
            stManager.updateCategorySocial(social)
            // Re-sync avec le social mis à jour
            let today = stManager.profileToday
            if today > 0 {
                let todayStr = ScreenTimeManager.dateFormatter.string(from: Date())
                Task { try? await APIClient.shared.syncScore(minutes: today, socialMinutes: social, date: todayStr) }
            }
        }
        .onPreferenceChange(WeekAvgKey.self) { avg in
            guard avg > 0 else { return }
            stManager.updateProfileWeekAvg(avg)
        }
        .onPreferenceChange(MonthAvgKey.self) { avg in
            guard avg > 0 else { return }
            stManager.updateProfileMonthAvg(avg)
        }
        .onPreferenceChange(HistoryKey.self) { raw in
            guard !raw.isEmpty else { return }
            stManager.updateProfileHistory(raw)
            // Re-syncer l'historique au backend (corrige les jours manqués par token expiré)
            // NE PAS envoyer socialMinutes — on n'a pas cette donnée ici et envoyer 0 écraserait le backend
            for entry in raw.split(separator: ",") {
                let parts = entry.split(separator: ":")
                guard parts.count == 2, let minutes = Int(parts[1]), minutes > 0, minutes <= 1440 else { continue }
                let dateStr = String(parts[0])
                Task { try? await APIClient.shared.syncScore(minutes: minutes, date: dateStr) }
            }
        }
        .sheet(isPresented: $showFriends) {
            FriendsView().environmentObject(appState)
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if stManager.pendingAuthRequest {
                stManager.pendingAuthRequest = false
                Task { await stManager.requestAuthorization() }
            }
        }) {
            SettingsView().environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showGroupDetail) {
            if let gid = selectedGroupId {
                SwipeDismissView {
                    GroupDetailView(groupId: gid, isSheet: true)
                        .environmentObject(appState)
                } onDismiss: { showGroupDetail = false }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                ScreenTimeManager.shared.loadProfileCache()
                ScreenTimeManager.shared.syncToBackend(appState: appState)
            }
        }
    }

    // MARK: - Today (total + social side by side)

    private func colorForMinutes(_ minutes: Int, goal: Int) -> Color {
        if minutes == 0 { return Theme.text }
        return minutes > goal ? Theme.red : Theme.green
    }

    private var todayStats: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(stManager.profileToday > 0 ? formatTime(stManager.profileToday) : "--")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(colorForMinutes(stManager.profileToday, goal: goalMinutes))
                Text(L10n.t("today").uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
                    .tracking(1.0)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Theme.separator).frame(width: 0.5, height: 48)

            VStack(spacing: 6) {
                Text(stManager.categorySocial > 0 ? formatTime(stManager.categorySocial) : "--")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(colorForMinutes(stManager.categorySocial, goal: Int(appState.socialGoalHours * 60)))
                Text(L10n.t("on_social_media").uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
                    .tracking(1.0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Streak

    @ViewBuilder
    private var streakBadge: some View {
        let streak = stManager.currentStreak
        if streak > 0 {
            HStack(spacing: 10) {
                Text("🔥")
                    .font(.system(size: 20))
                Text("\(streak) " + L10n.t("day_streak"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Theme.green.opacity(0.08))
            .cornerRadius(20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Week avg / Month avg

    private var avgStats: some View {
        HStack(spacing: 0) {
            avgCell(minutes: stManager.profileWeekAvg, label: L10n.t("week_avg"))
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.separator).frame(width: 0.5, height: 48)
            avgCell(minutes: stManager.profileMonthAvg, label: L10n.t("month_avg"))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    private func avgCell(minutes: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(minutes > 0 ? formatTime(minutes) : "--")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(1.0)
        }
        .frame(height: 56)
    }

    // MARK: - Week chart

    private var weekChart: some View {
        let data = stManager.profileHistory
        let goal = goalMinutes
        let maxM = max(data.map(\.minutes).max() ?? 1, goal, 1)
        return VStack(spacing: 0) {
            // Tapped day detail — score only, no over/under text
            if let id = tappedDay, let day = data.first(where: { $0.date == id }), day.minutes > 0 {
                HStack(spacing: 8) {
                    Text(day.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(formatTime(day.minutes))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(day.minutes > goal ? Theme.red : Theme.green)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                .transition(.opacity)
            }

            // Columns only — no score labels above bars
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(day.minutes > goal ? Theme.red.opacity(tappedDay == day.date ? 1.0 : 0.8) : (day.minutes > 0 ? Theme.green.opacity(tappedDay == day.date ? 1.0 : 0.7) : Theme.bgWarm))
                            .frame(height: max(4, CGFloat(day.minutes) / CGFloat(maxM) * 130))
                            .scaleEffect(x: tappedDay == day.date ? 1.15 : 1.0, y: 1.0, anchor: .bottom)
                        Text(day.label)
                            .font(.system(size: 12, weight: tappedDay == day.date ? .bold : .regular))
                            .foregroundColor(tappedDay == day.date ? Theme.text : Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tappedDay = tappedDay == day.date ? nil : day.date
                        }
                    }
                }
            }
            .frame(height: 160)

            HStack(spacing: 4) {
                Rectangle().fill(Theme.textFaint).frame(height: 0.5)
                Text("\(L10n.t("goal")) \(formatTime(goal))")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .padding(14)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.filter { $0.minutes > 0 }.map { "\($0.label): \(formatTime($0.minutes))" }.joined(separator: ", "))
    }

    // MARK: - Insight card

    @ViewBuilder
    private var insightCard: some View {
        let data = stManager.profileHistory
        let withData = data.filter { $0.minutes > 0 }
        let today = stManager.profileToday
        let weekAvg = stManager.profileWeekAvg

        if withData.count >= 2 || today > 0 {
            let insight = computeInsight(data: withData, today: today, weekAvg: weekAvg)
            if !insight.0.isEmpty {
                HStack(spacing: 12) {
                    Text(insight.0)
                        .font(.system(size: 22))
                    Text(insight.1)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
    }

    private func computeInsight(data: [ProfileDayData], today: Int, weekAvg: Int) -> (String, String) {
        let goal = goalMinutes
        // Best day this week
        if let best = data.min(by: { $0.minutes < $1.minutes }), best.minutes > 0 && data.count >= 3 {
            let bestLabel = best.label
            // Today vs average
            if today > 0 && weekAvg > 0 {
                let diff = weekAvg - today
                if diff > 15 {
                    return ("💪", "\(L10n.t("today")): \(formatTime(today)) — \(formatTime(diff)) \(L10n.t("under_goal_label").lowercased()) \(L10n.t("week_avg").lowercased())")
                } else if diff < -15 {
                    return ("📱", "\(L10n.t("today")): \(formatTime(today)) — \(formatTime(-diff)) \(L10n.t("over_goal_label")) \(L10n.t("week_avg").lowercased())")
                }
            }
            // Best day insight
            if best.minutes <= goal {
                return ("🏆", "\(L10n.t("best_day")): \(bestLabel) (\(formatTime(best.minutes)))")
            }
        }
        // Streak encouragement
        if stManager.currentStreak >= 3 {
            return ("🔥", "\(stManager.currentStreak) \(L10n.t("day_streak")) — \(L10n.t("under_goal_keep"))")
        }
        // Under goal today
        if today > 0 && today <= goal {
            return ("✅", "\(L10n.t("today")): \(formatTime(today)) — \(L10n.t("under_goal_keep"))")
        }
        return ("", "")
    }

    // MARK: - Header

    var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: { showFriends = true }) {
                    ZStack(alignment: .topTrailing) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2").font(.system(size: 15))
                            Text(L10n.t("friends")).font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Theme.textMuted)
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .liquidGlass(cornerRadius: 10)
                        if !fm.incomingRequests.isEmpty {
                            Circle().fill(Theme.red).frame(width: 10, height: 10).offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Friends")
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape").font(.system(size: 17))
                        .foregroundColor(Theme.textMuted).frame(width: 40, height: 40)
                        .liquidGlass(cornerRadius: 10)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 24).padding(.top, 60)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    if let uiImage = appState.profileUIImage {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(width: 88, height: 88).clipShape(Circle())
                    } else {
                        Circle().fill(Theme.bgWarm).frame(width: 88, height: 88)
                        Text(String(appState.userName.prefix(1)).uppercased())
                            .font(.system(size: 32, weight: .bold)).foregroundColor(Theme.textMuted)
                    }
                    Circle().fill(Theme.text).frame(width: 26, height: 26)
                        .overlay(Image(systemName: "camera").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.bg))
                        .offset(x: 30, y: 30)
                }
            }
            .onChange(of: selectedPhoto) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img  = UIImage(data: data) {
                        await MainActor.run { appState.saveImage(img) }
                    }
                }
            }

            Text(appState.userName).font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
        }
        .padding(.bottom, 28)
    }

    // MARK: - Groups summary

    var groupsSummary: some View {
        VStack(spacing: 0) {
            SectionTitle(text: L10n.t("active_challenges"))
            let active = appState.groups
            if active.isEmpty {
                Text(L10n.t("no_challenges"))
                    .font(.system(size: 15)).foregroundColor(Theme.textFaint)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(active) { group in
                        Button {
                            selectedGroupId = group.id
                            showGroupDetail = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                                    Text("\(group.daysLeft) \(L10n.t("days_remaining"))").font(.system(size: 14)).foregroundColor(Theme.textFaint)
                                }
                                Spacer()
                                if let rank = group.rankedMembers.firstIndex(where: { appState.isMe($0) }) {
                                    Text("#\(rank + 1)").font(.system(size: 22, weight: .bold))
                                        .foregroundColor(Theme.text)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textFaint)
                            }
                            .padding(18).liquidGlass(cornerRadius: 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}
