import SwiftUI
import PhotosUI
import DeviceActivity
import FamilyControls
import ManagedSettings

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
    @State private var darRefreshId: Int = 0
    @State private var darReceivedMinutes: Int = 0
    @State private var openURLReceivedMinutes: Int = 0
    @State private var tappedDay: String? = nil
    @State private var myAchievements: Set<String> = []
    @State private var showAllMedals = false
    @State private var showGroupDetail = false
    @State private var showAppPicker = false
    @State private var showReaderInfo = false
    @State private var autoPickAttempted = false

    private var hasAppSelection: Bool {
        !stManager.familySelection.applicationTokens.isEmpty ||
        !stManager.familySelection.categoryTokens.isEmpty
    }
    @State private var selectedGroupId: UUID? = nil
    @State private var headerAppeared = false
    @State private var statsAppeared = false
    @State private var chartAppeared = false
    @State private var medalsAppeared = false
    @State private var tappedMedalId: String?
    @State private var celebrateStreak = false
    var goalMinutes: Int { Int(appState.goalHours * 60) }

    private func startProfileRefresh() {
        guard !isTimerRunning else { return }
        isTimerRunning = true
        ScreenTimeManager.shared.loadProfileCache()
        // Relire toutes les 10 secondes + force DAR recompute
        profileRefreshTimer?.invalidate()
        profileRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            ScreenTimeManager.shared.loadProfileCache()
            // Don't change darRefreshId — it forces the DAR extension to
            // fully reload (white flash). The DAR renders once on appear
            // and stays stable. Only refresh on explicit pull-to-refresh.
        }
    }

    // Filter DAR to the SAME scope as DeviceActivityMonitor: user's family
    // selection, across all devices. This ensures the value displayed on
    // profile matches what the Monitor writes to App Group (no more DAR vs
    // DAM discrepancy). DeviceActivityEvent has no device filter, so DAM
    // always counts cross-device — we drop .iPhone from DAR to match.
    private var todayFilter: DeviceActivityFilter {
        let selection = stManager.familySelection
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Date())),
            users: .all,
            devices: .all,
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
    }

    /// DAR filter for today-only per-app breakdown. Hourly segment so the
    /// TodayScene sees only today's apps (it sums across the segment range).
    private var darTodayAppsFilter: DeviceActivityFilter {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: max(end, start.addingTimeInterval(60)))),
            devices: .init([.iPhone])
        )
    }

    /// DAR filter: 7 days for chart + today for apps. No app restriction.
    private var darProfileFilter: DeviceActivityFilter {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: end)) ?? end
        return DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(start: start, end: end)
            ),
            devices: .init([.iPhone])
        )
    }
    private var weekFilter: DeviceActivityFilter {
        // Use .hourly instead of .daily — .daily is buggy and gives wrong values
        // for today (partial day). The chart scene aggregates hourly into daily.
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            devices: .init([.iPhone])
        )
    }
    private var monthFilter: DeviceActivityFilter {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            devices: .init([.iPhone])
        )
    }

    var body: some View {
        ZStack {
            // Background
            Theme.bg.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    // DAR view — exact Apple screen time, no app filter restriction.
                    // Shows: today total + per-app breakdown + 14-day chart.
                    // Rendered by the extension with full access to Screen Time data.
                    // DAR exact screen time: today total + per-app breakdown.
                    // DeviceActivityReport needs explicit height — iOS doesn't
                    // report intrinsic size from extensions to the host.
                    // Screen time from the Opal-style background reader.
                    // Tracks ALL apps — no selection, no cheating.
                    todayScore
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    // Per-app breakdown — DAM-sourced, only populated for
                    // users who have picked specific apps to track. Shown
                    // only when there is data to avoid an empty box.
                    perAppDAMSection
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    // Silent auto-detection: if the user hasn't picked any
                    // tracked apps yet, render a tiny invisible DAR that
                    // emits AutoPickedTokensKey. On preference change we
                    // save the detected tokens and the Monitor takes over.
                    // DAR is used ONLY for this one-shot detection; once
                    // tokens are saved DAR plays no further role.
                    if stManager.trackedAppsTokens.isEmpty && !autoPickAttempted {
                        DeviceActivityReport(.init(rawValue: "todayTotal"), filter: darTodayAppsFilter)
                            .frame(width: 1, height: 1)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .onPreferenceChange(AutoPickedTokensKey.self) { jsonString in
                                handleAutoPicked(jsonString)
                            }
                    }

                    // 7-day chart — only reader data (App Group), no old sources
                    weekChart
                        .padding(.top, 16)
                        .padding(.horizontal, 24)

                    // My Events
                    MyEventsSection()
                        .padding(.top, 24)

                    Spacer().frame(height: 80)
                }
            }
            // DARs are inline in the scroll
        }
        .onAppear { 
            startProfileRefresh()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerAppeared = true
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                statsAppeared = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.3)) {
                chartAppeared = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.45)) {
                medalsAppeared = true
            }
        }
        .task {
            if let uid = AuthManager.shared.currentUser?.id {
                do {
                    let profile = try await APIClient.shared.getUserProfile(uid: uid)
                    await MainActor.run { myAchievements = Set(profile.achievements) }
                    Log.d("[Profile] Achievements loaded: \(profile.achievements)")
                } catch {
                    Log.e("[Profile] Failed to load achievements: \(error)")
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
            darReceivedMinutes = minutes
            // Diagnostic: log every fire, including 0, so we can distinguish
            // "preference never fires" from "preference fires with 0 minutes"
            Log.d("[PAKT Profile] TodayMinutesKey preference fired: \(minutes)")
            guard minutes > 0 else { return }
            let todayStr = ScreenTimeManager.dateFormatter.string(from: Date())
            UserDefaults.standard.set(minutes, forKey: UDKey.todayMinutes)
            UserDefaults.standard.set(todayStr, forKey: UDKey.todayDate)
            stManager.updateProfileToday(minutes)
            stManager.injectTodayIntoHistory(date: todayStr, minutes: minutes)
            let social = stManager.categorySocial
            // Use correctScore (direct assign) so DAR value can correct any
            // previously-stored inflated backend value.
            Task { try? await APIClient.shared.correctScore(minutes: minutes, socialMinutes: social > 0 ? social : nil, date: todayStr) }
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
        .familyActivityPicker(isPresented: $showAppPicker, selection: Binding(
            get: { stManager.familySelection },
            set: { newSelection in
                stManager.saveFamilySelection(newSelection)
                stManager.startBackgroundMonitoring()
            }
        ))
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

    // MARK: - Today score

    private func formatMinutes(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)min" }
        let h = mins / 60
        let m = mins % 60
        return m > 0 ? "\(h)h \(m)min" : "\(h)h"
    }

    private var todayScore: some View {
        VStack(spacing: 6) {
            Text(stManager.profileToday > 0 ? formatTime(stManager.profileToday) : "--")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(Theme.text)
                .contentTransition(.numericText())
            Text(L10n.t("today").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(1.5)
            Button {
                showReaderInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint.opacity(0.4))
            }
            .buttonStyle(.plain)
            .alert("Screen Time Tracker", isPresented: $showReaderInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("PAKT uses its own independent screen time tracker that runs in the background. Values may differ slightly from Apple's Screen Time in Settings, as we measure usage with our own system updated every 5 minutes.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Streak

    @ViewBuilder
    private var streakBadge: some View {
        let streak = stManager.currentStreak
        if streak > 0 {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.orange)
                    .scaleEffect(celebrateStreak ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5).repeatCount(3, autoreverses: true), value: celebrateStreak)
                Text("\(streak) " + L10n.t("day_streak"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Theme.green.opacity(0.08))
            .cornerRadius(20)
            .padding(.bottom, 16)
            .scaleEffect(statsAppeared ? 1.0 : 0.8)
            .opacity(statsAppeared ? 1.0 : 0.0)
            .onAppear {
                if streak >= 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        celebrateStreak = true
                    }
                }
            }
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

    // MARK: - Per-app breakdown (DAM-sourced, 100% consistent with today score)

    @ViewBuilder
    private var perAppDAMSection: some View {
        let entries = stManager.perAppBreakdown
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Apps trackées")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }

                VStack(spacing: 8) {
                    ForEach(entries, id: \.index) { entry in
                        perAppRow(entry: entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func perAppRow(entry: ScreenTimeManager.PerAppEntry) -> some View {
        HStack(spacing: 12) {
            Label(entry.token).labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
            Label(entry.token).labelStyle(.titleOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(formatAppMinutes(entry.minutes))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.bgCard)
        )
    }

    private func formatAppMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)min"
    }

    private func handleAutoPicked(_ jsonString: String) {
        guard !autoPickAttempted, !jsonString.isEmpty,
              stManager.trackedAppsTokens.isEmpty,
              let data = jsonString.data(using: .utf8),
              let tokens = try? JSONDecoder().decode([ApplicationToken].self, from: data),
              !tokens.isEmpty else {
            return
        }
        autoPickAttempted = true
        var selection = FamilyActivitySelection()
        selection.applicationTokens = Set(tokens)
        stManager.saveTrackedAppsSelection(selection)
        Log.d("[Profile] Auto-picked \(tokens.count) tracked apps from DAR")
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Columns only — no score labels above bars
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(day.minutes > goal ? Theme.red.opacity(tappedDay == day.date ? 1.0 : 0.8) : (day.minutes > 0 ? Theme.green.opacity(tappedDay == day.date ? 1.0 : 0.7) : Theme.bgWarm))
                            .frame(height: max(4, CGFloat(day.minutes) / CGFloat(maxM) * 130))
                            .scaleEffect(x: tappedDay == day.date ? 1.15 : 1.0, y: chartAppeared ? 1.0 : 0.01, anchor: .bottom)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.05), value: chartAppeared)
                        Text(day.label)
                            .font(.system(size: 12, weight: tappedDay == day.date ? .bold : .regular))
                            .foregroundColor(tappedDay == day.date ? Theme.text : Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        // Haptic feedback
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.4))
        )
        .liquidGlass(cornerRadius: 16, style: .ultraThin)
        .padding(.top, 20)
        .scaleEffect(chartAppeared ? 1.0 : 0.9)
        .opacity(chartAppeared ? 1.0 : 0.0)
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
                    Image(systemName: insight.0)
                        .font(.system(size: 18))
                        .foregroundColor(Theme.orange)
                    Text(insight.1)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.4))
                )
                .liquidGlass(cornerRadius: 14, style: .ultraThin)
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
                    return ("arrow.down.circle.fill", "\(L10n.t("today")): \(formatTime(today)) — \(formatTime(diff)) \(L10n.t("under_goal_label").lowercased()) \(L10n.t("week_avg").lowercased())")
                } else if diff < -15 {
                    return ("arrow.up.circle.fill", "\(L10n.t("today")): \(formatTime(today)) — \(formatTime(-diff)) \(L10n.t("over_goal_label")) \(L10n.t("week_avg").lowercased())")
                }
            }
            // Best day insight
            if best.minutes <= goal {
                return ("star.circle.fill", "\(L10n.t("best_day")): \(bestLabel) (\(formatTime(best.minutes)))")
            }
        }
        // Streak encouragement
        if stManager.currentStreak >= 3 {
            return ("flame.fill", "\(stManager.currentStreak) \(L10n.t("day_streak")) — \(L10n.t("under_goal_keep"))")
        }
        // Under goal today
        if today > 0 && today <= goal {
            return ("checkmark.circle.fill", "\(L10n.t("today")): \(formatTime(today)) — \(L10n.t("under_goal_keep"))")
        }
        return ("", "")
    }

    // MARK: - Medals card

    private var medalsCard: some View {
        let count = myAchievements.count
        let total = AchievementDef.all.count
        let previewCount = 6
        let items = showAllMedals ? AchievementDef.all : Array(AchievementDef.all.prefix(previewCount))

        return VStack(spacing: 14) {
            // Header
            HStack {
                Text(L10n.t("medals"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
                    .tracking(1.6)
                Spacer()
                Text("\(count)/\(total)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
                    .contentTransition(.numericText())
            }

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, achievement in
                    let unlocked = myAchievements.contains(achievement.id)
                    let isTapped = tappedMedalId == achievement.id
                    
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(unlocked ? achievement.color.opacity(0.15) : Theme.bgWarm)
                                .frame(width: 40, height: 40)
                            Image(systemName: achievement.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(unlocked ? achievement.color : Theme.textFaint)
                                .symbolEffect(.bounce, value: isTapped)
                        }
                        .scaleEffect(isTapped ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTapped)
                        
                        Text(achievement.name)
                            .font(.system(size: 11, weight: unlocked ? .semibold : .regular))
                            .foregroundColor(unlocked ? Theme.text : Theme.textFaint)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 28)
                    }
                    .opacity(unlocked ? 1.0 : 0.4)
                    .scaleEffect(medalsAppeared ? 1.0 : 0.5)
                    .opacity(medalsAppeared ? (unlocked ? 1.0 : 0.4) : 0.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.04), value: medalsAppeared)
                    .onTapGesture {
                        if unlocked {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            
                            withAnimation {
                                tappedMedalId = achievement.id
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    tappedMedalId = nil
                                }
                            }
                        }
                    }
                }
            }

            // Show more / less
            if AchievementDef.all.count > previewCount {
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showAllMedals.toggle() } }) {
                    HStack(spacing: 6) {
                        Text(showAllMedals ? L10n.t("done") : L10n.t("see_all"))
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: showAllMedals ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(showAllMedals ? 0 : 180))
                    }
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.4))
        )
        .liquidGlass(cornerRadius: 16, style: .ultraThin)
        .scaleEffect(medalsAppeared ? 1.0 : 0.9)
        .opacity(medalsAppeared ? 1.0 : 0.0)
    }

    // MARK: - Header

    var header: some View {
        VStack(spacing: 20) {
            // Title row
            HStack {
                Text(L10n.t("profile"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { showFriends = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "person.2")
                                .font(.system(size: 15))
                                .foregroundColor(Theme.textMuted)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                )
                            if !fm.incomingRequests.isEmpty {
                                Circle()
                                    .fill(Theme.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 2, y: -2)
                                    .scaleEffect(headerAppeared ? 1.0 : 0.0)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.3), value: headerAppeared)
                            }
                        }
                    }
                    .accessibilityLabel(L10n.t("friends"))
                    .scaleEffect(headerAppeared ? 1.0 : 0.5)
                    .opacity(headerAppeared ? 1.0 : 0.0)
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .accessibilityLabel(L10n.t("settings"))
                    .scaleEffect(headerAppeared ? 1.0 : 0.5)
                    .opacity(headerAppeared ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, 24).padding(.top, 56)

            // Avatar + name (centered)
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

            Text(appState.userName)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
        }
        .padding(.bottom, 20)
    }

}
