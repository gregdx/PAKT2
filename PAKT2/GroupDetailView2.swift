import SwiftUI
import Combine

struct GroupDetailView: View {
    let groupId: UUID
    var isSheet: Bool = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showEdit = false
    @State private var showResult = false
    @State private var period: Period = .total
    @State private var isRefreshing = false
    @State private var isSyncing = true
    @State private var selectedMemberUID: String?
    @State private var invitedIds: Set<String> = []
    @ObservedObject private var friendManager = FriendManager.shared
    @ObservedObject private var stManager = ScreenTimeManager.shared
    @ObservedObject private var chatManager = ActivityManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showGroupChat = false
    @State private var activeTab: GroupTab = .ranking

    enum GroupTab: String, CaseIterable {
        case ranking, data, messages
    }

    private var groupOpt: Group? {
        appState.groups.first { $0.id == groupId }
    }

    var group: Group {
        groupOpt ?? Group(name: "", code: "", mode: .competitive, goalMinutes: 180, duration: .oneMonth, startDate: Date(), members: [], status: .pending)
    }

    private func minutesFor(_ member: Member) -> Int {
        guard groupOpt != nil else { return 0 }
        switch period {
        case .day:   return group.todayRankMinutes(member)
        case .total: return group.rankMinutes(member)
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if groupOpt == nil {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .onAppear { dismiss() }
            } else {
                VStack(spacing: 0) {
                    // Fixed header + tab picker
                    detailHeader

                    if group.isPending || !group.hasStarted || isSyncing {
                        // Non-active states: scrollable
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                if group.isPending {
                                    pendingPaktView
                                } else if !group.hasStarted {
                                    VStack(spacing: 24) {
                                        Spacer().frame(height: 40)
                                        Image(systemName: "moon.zzz.fill")
                                            .font(.system(size: 48))
                                            .foregroundColor(Theme.textFaint)
                                        Text(L10n.t("starts_midnight"))
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(Theme.text)
                                        Text(L10n.t("challenge_begins_midnight"))
                                            .font(.system(size: 15))
                                            .foregroundColor(Theme.textMuted)
                                            .multilineTextAlignment(.center)
                                            .lineSpacing(4)
                                        VStack(spacing: 0) {
                                            ForEach(Array(group.members.enumerated()), id: \.element.id) { i, member in
                                                HStack(spacing: 12) {
                                                    AvatarView(name: member.name, size: 40, color: Theme.textMuted,
                                                               uid: member.uid, isMe: appState.isMe(member))
                                                        .environmentObject(appState)
                                                    Text(member.name)
                                                        .font(.system(size: 16, weight: .medium))
                                                        .foregroundColor(Theme.text)
                                                    Spacer()
                                                    Text("--")
                                                        .font(.system(size: 18, weight: .bold))
                                                        .foregroundColor(Theme.textFaint)
                                                }
                                                .padding(.horizontal, 16).padding(.vertical, 12)
                                                if i < group.members.count - 1 {
                                                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 68)
                                                }
                                            }
                                        }
                                        .liquidGlass(cornerRadius: 16)
                                        .padding(.horizontal, 24)
                                    }
                                } else {
                                    ProgressView().padding(.top, 60)
                                }
                                Spacer().frame(height: 100)
                            }
                        }
                    } else {
                        // Active group: tab picker + swipable content
                        challengeBanner
                        groupTabBar

                        TabView(selection: $activeTab) {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 0) {
                                    rankingTabContent
                                    Spacer().frame(height: 100)
                                }
                            }
                            .tag(GroupTab.ranking)

                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 0) {
                                    membersTabContent
                                    Spacer().frame(height: 100)
                                }
                            }
                            .tag(GroupTab.data)

                            GroupChatView(group: group, inline: true)
                                .environmentObject(appState)
                                .tag(GroupTab.messages)
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        .animation(.easeInOut(duration: 0.25), value: activeTab)
                        .ignoresSafeArea(.keyboard)
                    }
                }
            } // else
        }
        .navigationBarHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            isSyncing = false

            guard groupOpt != nil else { return }
            // Appliquer immédiatement les données locales (extension) au groupe
            ScreenTimeManager.shared.loadProfileCache()
            ScreenTimeManager.shared.updateLocalGroups(appState: appState)
            // Puis sync + fetch pour les données des amis
            ScreenTimeManager.shared.syncToBackend(appState: appState)
            let uid = appState.currentUID
            if !uid.isEmpty {
                ScreenTimeManager.shared.fetchSinceStartCumulative(uid: uid, appState: appState, force: true)
            }
            // Charger les scores pour le graphe de course
            await loadChartScores()

            try? await Task.sleep(nanoseconds: 500_000_000)
            if let g = groupOpt, g.isCompleted && !g.isFinished && !g.isPending {
                showResult = true
            }
        }
        .sheet(isPresented: $showEdit) {
            if groupOpt != nil {
                EditGroupView(group: group).environmentObject(appState)
            }
        }
        .sheet(isPresented: $showResult) {
            if groupOpt != nil {
                ChallengeResultView(group: group).environmentObject(appState)
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedMemberUID != nil },
            set: { if !$0 { selectedMemberUID = nil } }
        )) {
            if let uid = selectedMemberUID,
               let member = group.members.first(where: { $0.uid == uid }) {
                let sorted = group.members.sorted { minutesFor($0) < minutesFor($1) }
                let rank = (sorted.firstIndex(where: { $0.uid == uid }) ?? 0) + 1
                MemberProfileView(member: member, rank: rank, total: sorted.count, group: group)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Extracted Sub-Views

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("Close")
            Spacer()
            Text(group.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
            ShareLink(item: "\(L10n.t("invite_message")) \(group.code)\nhttps://pakt-app.com/join/\(group.code)") {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("Share group")
            Button(action: { showEdit = true }) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("Edit group")
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
    }

    // MARK: - Group Tab Picker

    private var groupTabBar: some View {
        HStack(spacing: 8) {
            ForEach(GroupTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                }) {
                    Text(tabLabel(tab))
                        .font(.system(size: 15, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundColor(activeTab == tab ? Theme.bg : Theme.textMuted)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background {
                            if activeTab == tab {
                                RoundedRectangle(cornerRadius: 20).fill(Theme.text)
                            } else {
                                RoundedRectangle(cornerRadius: 20).fill(.clear).liquidGlass(cornerRadius: 20)
                            }
                        }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func tabLabel(_ tab: GroupTab) -> String {
        switch tab {
        case .ranking:  return L10n.t("ranking_tab")
        case .data:     return L10n.t("stats_tab")
        case .messages: return L10n.t("messages_tab")
        }
    }

    // MARK: - Ranking Tab (final + today)

    private var rankingTabContent: some View {
        VStack(spacing: 24) {
            // Daily highlight card
            dailyHighlight

            // Podium top 3
            podiumView

            // Rest of ranking (#4+)
            restOfRankingList

            // Today ranking
            VStack(spacing: 8) {
                SectionTitle(text: L10n.t("ranking_today"))
                    .padding(.horizontal, 24)
                todayRankingList
            }

            challengeProgress
            rulesSection
        }
    }

    // MARK: - Daily Highlight

    private var dailyHighlight: some View {
        let sorted = group.members.sorted { group.todayRankMinutes($0) < group.todayRankMinutes($1) }
        let leader = sorted.first
        let underGoal = sorted.filter { group.todayRankMinutes($0) > 0 && group.todayRankMinutes($0) <= group.goalMinutes }

        let message: String = {
            if let l = leader, group.todayRankMinutes(l) > 0 {
                return "\(l.name) leads today with \(formatTime(group.todayRankMinutes(l)))"
            }
            if !underGoal.isEmpty {
                return "\(underGoal.count) members under goal today"
            }
            return "Day \(group.duration.days - group.daysLeft) of \(group.duration.days)"
        }()

        return HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.orange)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.text)
            Spacer()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 12)
        .padding(.horizontal, 24)
    }

    // MARK: - Podium (Top 3)

    private var podiumView: some View {
        let sorted = group.members.sorted { group.rankMinutes($0) < group.rankMinutes($1) }
        let top3 = Array(sorted.prefix(3))

        return HStack(alignment: .bottom, spacing: 20) {
            // 2nd place (left)
            if top3.count > 1 {
                podiumColumn(member: top3[1], rank: 2)
            }
            // 1st place (center, biggest)
            if let first = top3.first {
                podiumColumn(member: first, rank: 1)
            }
            // 3rd place (right)
            if top3.count > 2 {
                podiumColumn(member: top3[2], rank: 3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func podiumColumn(member: Member, rank: Int) -> some View {
        let avatarSize: CGFloat = rank == 1 ? 80 : 60
        let rankColor: Color = rank == 1 ? Theme.green : (rank == 2 ? Theme.blue : Theme.orange)
        let mins = group.rankMinutes(member)

        return VStack(spacing: 6) {
            // Avatar with ring and glow for #1
            ZStack {
                if rank == 1 {
                    // Subtle radial glow behind #1
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Theme.green.opacity(0.20), Theme.green.opacity(0.0)]),
                                center: .center,
                                startRadius: avatarSize * 0.3,
                                endRadius: avatarSize * 0.8
                            )
                        )
                        .frame(width: avatarSize + 20, height: avatarSize + 20)
                }
                AvatarView(name: member.name, size: avatarSize, color: rankColor,
                           uid: member.uid, isMe: appState.isMe(member))
                    .environmentObject(appState)
                    .overlay(
                        Circle()
                            .stroke(rankColor, lineWidth: rank == 1 ? 3 : 2)
                    )
            }

            Text("#\(rank)")
                .font(.system(size: rank == 1 ? 14 : 12, weight: .black))
                .foregroundColor(rankColor)

            Text(member.name)
                .font(.system(size: rank == 1 ? 16 : 14, weight: .bold))
                .foregroundColor(Theme.text)
                .lineLimit(1)

            Text(mins > 0 ? formatTime(mins) : "--")
                .font(.system(size: rank == 1 ? 22 : 17, weight: .bold))
                .foregroundColor(rank == 1 ? Theme.green : Theme.text)

            // Subtle colored line under each column (replaces tall block)
            RoundedRectangle(cornerRadius: 2)
                .fill(rankColor.opacity(rank == 1 ? 0.5 : 0.3))
                .frame(height: 3)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rest of Ranking (#4+)

    private var restOfRankingList: some View {
        let sorted = group.members.sorted { group.rankMinutes($0) < group.rankMinutes($1) }
        let rest = Array(sorted.dropFirst(3))

        return VStack(spacing: 0) {
            ForEach(Array(rest.enumerated()), id: \.element.id) { i, member in
                let rank = i + 4
                let mins = group.rankMinutes(member)

                Button { selectedMemberUID = member.uid } label: {
                    HStack(spacing: 14) {
                        Text("#\(rank)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 30, alignment: .leading)

                        AvatarView(name: member.name, size: 44, color: Theme.textMuted,
                                   uid: member.uid, isMe: appState.isMe(member))
                            .environmentObject(appState)

                        Text(member.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.text)

                        Spacer()

                        Text(mins > 0 ? formatTime(mins) : "--")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(mins == 0 ? Theme.textFaint : Theme.text)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16).padding(.vertical, 12)

                if i < rest.count - 1 {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 68)
                }
            }
        }
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
    }

    private var todayRankingList: some View {
        let sorted = group.members.sorted { group.todayRankMinutes($0) < group.todayRankMinutes($1) }
        return VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, member in
                let rank = i + 1
                let mins = group.todayRankMinutes(member)
                let isTop3 = rank <= 3
                let rankColor: Color = rank == 1 ? Theme.green : (rank == 2 ? Theme.blue : (rank == 3 ? Theme.orange : Theme.textFaint))

                HStack(spacing: 12) {
                    // Rank number with colored background for top 3
                    ZStack {
                        if isTop3 {
                            Circle()
                                .fill(rankColor.opacity(0.12))
                                .frame(width: 28, height: 28)
                        }
                        Text("\(rank)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isTop3 ? rankColor : Theme.textFaint)
                    }
                    .frame(width: 28)

                    AvatarView(name: member.name, size: 40, color: isTop3 ? rankColor : Theme.textMuted,
                               uid: member.uid, isMe: appState.isMe(member))
                        .environmentObject(appState)
                        .overlay(
                            isTop3 ? Circle().stroke(rankColor.opacity(0.4), lineWidth: 1.5) : nil
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(mins > 0 ? formatTime(mins) : "--")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(mins == 0 ? Theme.textFaint : (rank == 1 ? Theme.green : Theme.text))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                if i < sorted.count - 1 {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 64)
                }
            }
        }
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
    }

    // MARK: - Members Tab (stats, graphs, profiles)

    private var membersTabContent: some View {
        VStack(spacing: 20) {
            // 1. Horizontal scroll stat bubbles
            statsHorizontalScroll

            // 2. Award cards
            awardsSection

            // 3. Goal distribution
            goalDistribution

            // 4. Race chart
            raceChart

            // 5. Compact member list
            compactMemberList
        }
    }

    // MARK: - Stats Horizontal Scroll

    private var statsHorizontalScroll: some View {
        let totalMinutesUsed = group.members.reduce(0) { $0 + group.rankMinutes($1) }
        let daysElapsed = max(1, group.duration.days - group.daysLeft)
        let expectedMinutes = group.members.count * daysElapsed * 240
        let savedMinutes = max(0, expectedMinutes - totalMinutesUsed)

        let memberDaysUnderGoal = group.members.reduce(0) { total, m in
            total + m.history.filter { $0.minutes > 0 && $0.minutes <= group.goalMinutes }.count
        }
        let totalMemberDays = group.members.reduce(0) { total, m in
            total + m.history.filter { $0.minutes > 0 }.count
        }
        let successRate = totalMemberDays > 0 ? (memberDaysUnderGoal * 100 / totalMemberDays) : 0

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                statBubble(
                    value: formatTime(group.averageMinutes),
                    label: L10n.t("group_avg_today"),
                    icon: "person.3",
                    color: group.averageMinutes <= group.goalMinutes ? Theme.green : Theme.red
                )
                statBubble(
                    value: "\(savedMinutes / 60)h",
                    label: L10n.t("hours_saved"),
                    icon: "arrow.down.circle",
                    color: Theme.green
                )
                statBubble(
                    value: "\(successRate)%",
                    label: L10n.t("success_rate"),
                    icon: "checkmark.circle",
                    color: successRate >= 50 ? Theme.green : Theme.orange
                )
            }
            .padding(.horizontal, 24)
        }
    }

    private func statBubble(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140)
        .padding(.vertical, 20)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Awards Section

    private var awardsSection: some View {
        let members = group.members.filter { !$0.history.isEmpty }

        // Most improved: member whose last 3 days avg is lowest compared to first 3 days
        let mostImproved: (member: Member, detail: String)? = {
            let candidates = members.filter { $0.history.filter({ $0.minutes > 0 }).count >= 4 }
            guard !candidates.isEmpty else { return nil }
            var best: (Member, Int)? = nil
            for m in candidates {
                let active = m.history.filter { $0.minutes > 0 }
                let first3 = active.prefix(3).map { $0.minutes }
                let last3 = active.suffix(3).map { $0.minutes }
                guard !first3.isEmpty, !last3.isEmpty else { continue }
                let firstAvg = first3.reduce(0, +) / first3.count
                let lastAvg = last3.reduce(0, +) / last3.count
                let diff = lastAvg - firstAvg
                if best == nil || diff < best!.1 { best = (m, diff) }
            }
            guard let b = best else { return nil }
            let sign = b.1 <= 0 ? "" : "+"
            return (b.0, "\(sign)\(b.1)min vs start")
        }()

        // Most consistent: lowest standard deviation
        let mostConsistent: (member: Member, detail: String)? = {
            guard !members.isEmpty else { return nil }
            var best: (Member, Double)? = nil
            for m in members {
                let vals = m.history.filter { $0.minutes > 0 }.map { Double($0.minutes) }
                guard vals.count >= 3 else { continue }
                let mean = vals.reduce(0, +) / Double(vals.count)
                let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(vals.count)
                let stdDev = sqrt(variance)
                if best == nil || stdDev < best!.1 { best = (m, stdDev) }
            }
            guard let b = best else { return nil }
            return (b.0, "std dev: \(Int(b.1))min")
        }()

        // Best single day: lowest single day across all members
        let bestSingleDay: (member: Member, detail: String)? = {
            var best: (Member, DataPoint)? = nil
            for m in members {
                for dp in m.history where dp.minutes > 0 {
                    if best == nil || dp.minutes < best!.1.minutes { best = (m, dp) }
                }
            }
            guard let b = best else { return nil }
            return (b.0, "\(formatTime(b.1.minutes)) — \(b.1.day)")
        }()

        // Worst single day: highest single day across all members
        let worstSingleDay: (member: Member, detail: String)? = {
            var worst: (Member, DataPoint)? = nil
            for m in members {
                for dp in m.history where dp.minutes > 0 {
                    if worst == nil || dp.minutes > worst!.1.minutes { worst = (m, dp) }
                }
            }
            guard let w = worst else { return nil }
            return (w.0, "\(formatTime(w.1.minutes)) — \(w.1.day)")
        }()

        // Closest to goal: member whose average is closest to the goal
        let closestToGoal: (member: Member, detail: String)? = {
            guard !members.isEmpty else { return nil }
            var best: (Member, Int)? = nil
            for m in members {
                let avg = m.monthAvgMinutes
                guard avg > 0 else { continue }
                let diff = abs(avg - group.goalMinutes)
                if best == nil || diff < best!.1 { best = (m, diff) }
            }
            guard let b = best else { return nil }
            let avg = b.0.monthAvgMinutes
            let delta = avg - group.goalMinutes
            let sign = delta <= 0 ? "" : "+"
            return (b.0, "avg \(formatTime(avg)) (\(sign)\(delta)min)")
        }()

        return VStack(spacing: 10) {
            SectionTitle(text: L10n.t("awards"))
                .padding(.horizontal, 24)

            if let a = mostImproved {
                awardCard(title: L10n.t("most_improved"), member: a.member, detail: a.detail, icon: "chart.line.downtrend.xyaxis", color: Theme.green)
            }
            if let a = mostConsistent {
                awardCard(title: L10n.t("most_consistent"), member: a.member, detail: a.detail, icon: "metronome", color: Theme.blue)
            }
            if let a = bestSingleDay {
                awardCard(title: L10n.t("best_single_day"), member: a.member, detail: a.detail, icon: "star", color: Theme.green)
            }
            if let a = worstSingleDay {
                awardCard(title: L10n.t("worst_single_day"), member: a.member, detail: a.detail, icon: "flame", color: Theme.red)
            }
            if let a = closestToGoal {
                awardCard(title: L10n.t("closest_to_goal"), member: a.member, detail: a.detail, icon: "target", color: Theme.orange)
            }
        }
    }

    private func awardCard(title: String, member: Member, detail: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: member.name, size: 48, color: color, uid: member.uid, isMe: appState.isMe(member))
                .environmentObject(appState)
                .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                    .tracking(1)
                Text(member.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
    }

    // MARK: - Compact Member List

    private var compactMemberList: some View {
        VStack(spacing: 6) {
            ForEach(group.members, id: \.id) { member in
                Button { selectedMemberUID = member.uid } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: member.name, size: 36, color: Theme.textMuted,
                                   uid: member.uid, isMe: appState.isMe(member))
                            .environmentObject(appState)
                        Text(member.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Text(formatTime(member.todayMinutes))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(member.todayMinutes <= group.goalMinutes ? Theme.green : Theme.textMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textFaint)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var challengeBanner: some View {
        if group.isCompleted {
            Button(action: { showResult = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.green)
                    Text(L10n.t("challenge_complete"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textFaint)
                }
                .padding(16)
                .background(Theme.green.opacity(0.08))
                .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // (old periodPicker and rankingList removed — replaced by groupTabBar + finalRankingList/todayRankingList)

    // MARK: - Race Chart (inline — courbes cumulatives par membre)

    private var raceChart: some View {
        let df = ScreenTimeManager.dateFormatter
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: group.startDate)
        let today = cal.startOfDay(for: Date())
        let totalDays = max(1, cal.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1
        let allDates: [String] = (0..<totalDays).map { i in
            df.string(from: cal.date(byAdding: .day, value: i, to: startDay) ?? Date())
        }
        let shortFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM"; f.locale = Locale(identifier: "en_US"); return f }()
        let dayLabels: [String] = allDates.map { dateStr in
            let d = df.date(from: dateStr) ?? Date()
            return shortFmt.string(from: d)
        }
        let members = group.members

        // Cumulative totals per member
        var cumulativeScores: [String: [String: Int]] = [:]
        for m in members {
            var runningTotal = 0
            for dateStr in allDates {
                let dayMins = chartScores[m.uid]?.first(where: { $0.date == dateStr })?.minutes ?? 0
                runningTotal += dayMins
                cumulativeScores[m.uid, default: [:]][dateStr] = runningTotal
            }
        }
        let allValues = members.flatMap { m in allDates.map { d in cumulativeScores[m.uid]?[d] ?? 0 } }
        let maxY = max(allValues.max() ?? 1, 1)

        // Colors
        let finalTotals = members.compactMap { m -> (String, Int)? in
            guard let total = cumulativeScores[m.uid]?[allDates.last ?? ""], total > 0 else { return nil }
            return (m.uid, total)
        }
        let bestUid = finalTotals.min(by: { $0.1 < $1.1 })?.0
        let worstUid = finalTotals.max(by: { $0.1 < $1.1 })?.0
        let memberColors: [String: Color] = Dictionary(uniqueKeysWithValues: members.map { m in
            if m.uid == bestUid { return (m.uid, Theme.green) }
            if m.uid == worstUid && finalTotals.count > 1 { return (m.uid, Theme.red) }
            return (m.uid, Theme.text.opacity(0.5))
        })

        return VStack(spacing: 12) {
            VStack(spacing: 0) {
                if chartLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.textFaint)
                        Text(L10n.t("loading")).font(.system(size: 13)).foregroundColor(Theme.textFaint)
                    }
                    .frame(height: 180)
                } else {
                    // Curve chart
                    GeometryReader { geo in
                        let w = geo.size.width - 16
                        let h: CGFloat = 180
                        let stepX = w / CGFloat(max(allDates.count - 1, 1))

                        ZStack(alignment: .topLeading) {
                            // Grid lines
                            ForEach(0..<3, id: \.self) { i in
                                let y = h * CGFloat(i) / 2.0
                                Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                                    .stroke(Theme.separator.opacity(0.2), lineWidth: 0.5)
                            }

                            // Member curves
                            ForEach(members, id: \.id) { member in
                                let points: [CGPoint] = allDates.enumerated().map { i, dateStr in
                                    let cumul = cumulativeScores[member.uid]?[dateStr] ?? 0
                                    let x = stepX * CGFloat(i)
                                    let y = cumul > 0 ? h * (1.0 - CGFloat(cumul) / CGFloat(maxY)) : h
                                    return CGPoint(x: x, y: y)
                                }
                                let color = memberColors[member.uid] ?? Theme.textMuted

                                Path { path in
                                    guard let first = points.first else { return }
                                    path.move(to: first)
                                    for i in 1..<points.count {
                                        let prev = points[i - 1]
                                        let cur = points[i]
                                        let midX = (prev.x + cur.x) / 2
                                        path.addCurve(to: cur, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: cur.y))
                                    }
                                }
                                .stroke(color, lineWidth: 2.5)

                                // Avatar at last point
                                if let last = points.last {
                                    AvatarView(name: member.name, size: 22, color: color,
                                               uid: member.uid, isMe: appState.isMe(member))
                                        .environmentObject(appState)
                                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                                        .position(x: last.x, y: last.y)
                                }
                            }
                        }
                        .frame(height: h)
                    }
                    .frame(height: 180)

                    // X axis — only show first, middle, last
                    if allDates.count > 1 {
                        HStack {
                            Text(dayLabels.first ?? "")
                            Spacer()
                            if dayLabels.count > 2 { Text(dayLabels[dayLabels.count / 2]) }
                            Spacer()
                            Text(dayLabels.last ?? "")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Group Overview (visual with avatars)

    private var groupOverview: some View {
        let members = group.members
        let activeMembers = members.filter { minutesFor($0) > 0 }
        let best = activeMembers.min(by: { minutesFor($0) < minutesFor($1) })
        let underGoalMembers = activeMembers.filter { minutesFor($0) <= group.goalMinutes }

        return VStack(spacing: 16) {
            // Best performer
            if let best = best {
                VStack(spacing: 10) {
                    Text(L10n.t("best"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textFaint)
                        .tracking(1.5)
                    AvatarView(name: best.name, size: 56, color: Theme.green,
                               uid: best.uid, isMe: appState.isMe(best))
                        .environmentObject(appState)
                        .overlay(Circle().stroke(Theme.green, lineWidth: 2))
                    Text(best.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(formatTime(minutesFor(best)))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .liquidGlass(cornerRadius: 16)
            }

            // Under goal — avatars row
            if !underGoalMembers.isEmpty {
                VStack(spacing: 10) {
                    Text(L10n.t("under_goal_label"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textFaint)
                        .tracking(1.5)
                    HStack(spacing: -6) {
                        ForEach(underGoalMembers.prefix(8), id: \.id) { member in
                            AvatarView(name: member.name, size: 36, color: Theme.green,
                                       uid: member.uid, isMe: appState.isMe(member))
                                .environmentObject(appState)
                                .overlay(Circle().stroke(Theme.green.opacity(0.5), lineWidth: 1.5))
                        }
                    }
                    Text("\(underGoalMembers.count)/\(activeMembers.count)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .liquidGlass(cornerRadius: 16)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Chart data loading

    @State private var chartScores: [String: [(date: String, minutes: Int)]] = [:]
    @State private var chartLoading = true

    private func loadChartScores() async {
        let df = ScreenTimeManager.dateFormatter
        let since = df.string(from: Calendar.current.startOfDay(for: group.startDate))
        guard let scores = try? await APIClient.shared.getGroupScores(groupID: group.id.uuidString, since: since) else {
            await MainActor.run { chartLoading = false }
            return
        }
        var result: [String: [(date: String, minutes: Int)]] = [:]
        for s in scores {
            result[s.userId, default: []].append((date: s.date, minutes: s.minutes))
        }
        await MainActor.run {
            chartScores = result
            chartLoading = false
        }
    }

    // MARK: - Goal Distribution (green/red split bar)

    private var goalDistribution: some View {
        let activeMembers = group.members.filter { minutesFor($0) > 0 }
        let underGoal = activeMembers.filter { minutesFor($0) <= group.goalMinutes }.count
        let overGoal = activeMembers.count - underGoal
        let total = max(activeMembers.count, 1)

        return VStack(spacing: 12) {
            SectionTitle(text: L10n.t("goal"))
                .padding(.horizontal, 24)

            VStack(spacing: 14) {
                // Split bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.green)
                            .frame(width: max(8, geo.size.width * CGFloat(underGoal) / CGFloat(total)))
                        if overGoal > 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.red.opacity(0.7))
                        }
                    }
                }
                .frame(height: 24)

                // Legend
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.green).frame(width: 8, height: 8)
                        Text("\(underGoal) " + L10n.t("under_goal"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Theme.red.opacity(0.7)).frame(width: 8, height: 8)
                        Text("\(overGoal) " + L10n.t("over_goal_label"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                }

                // Goal line label
                Text("\(L10n.t("goal")): \(formatTime(group.goalMinutes))")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(16)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Challenge Progress (simplified)

    private var challengeProgress: some View {
        VStack(spacing: 12) {
            SectionTitle(text: L10n.t("progress"))
                .padding(.horizontal, 24)

            VStack(spacing: 16) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.bgCard)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.text.opacity(0.6))
                            .frame(width: geo.size.width * group.challengeProgress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(group.daysLeft) " + L10n.t("days_remaining"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                    Text("\(Int(group.challengeProgress * 100))%")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.text)
                }
            }
            .padding(18)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: L10n.t("rules"))
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(systemName: group.mode == .competitive ? "person.3.fill" : "hands.clap.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textMuted)
                    Text(group.mode.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Theme.separator).frame(width: 0.5, height: 40)

                VStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.orange)
                    Text(group.stake)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Theme.separator).frame(width: 0.5, height: 40)

                VStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textMuted)
                    Text("\(formatTime(group.goalMinutes))\(L10n.t("per_day"))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(18)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 24)
        }
    }

    private var pendingPaktView: some View {
        VStack(spacing: 24) {
            // Stake
            VStack(spacing: 8) {
                Text(L10n.t("stake_label"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textFaint).tracking(1.6)
                Text(group.stake)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 24)

            // Signature progress
            VStack(spacing: 16) {
                Text("\(group.members.count) / \(group.requiredPlayers)")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(Theme.orange)

                // Signed members
                VStack(spacing: 0) {
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { i, member in
                        HStack(spacing: 12) {
                            AvatarView(name: member.name, size: 36, color: Theme.textMuted,
                                       uid: member.uid, isMe: appState.isMe(member))
                                .environmentObject(appState)
                            Text(member.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Theme.text)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.green)
                                .font(.system(size: 18))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if i < group.members.count - 1 || group.signaturesNeeded > 0 {
                            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 56)
                        }
                    }

                    // Empty slots
                    ForEach(0..<group.signaturesNeeded, id: \.self) { i in
                        HStack(spacing: 12) {
                            Circle().fill(Theme.bgWarm).frame(width: 36, height: 36)
                                .overlay(Text("?").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.textFaint))
                            Text(L10n.t("waiting_signature"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Theme.textFaint)
                            Spacer()
                            Image(systemName: "circle.dashed")
                                .foregroundColor(Theme.textFaint)
                                .font(.system(size: 18))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if i < group.signaturesNeeded - 1 {
                            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 56)
                        }
                    }
                }
                .liquidGlass(cornerRadius: 12)
            }
            .padding(.horizontal, 24)

            // Invite friends inline
            inviteFriendsSection

            // Start now button (creator only, if at least 2 members)
            if group.creatorId == appState.currentUID && group.members.count >= 2 {
                Button(action: {
                    Task {
                        if let apiGroup = try? await APIClient.shared.startGroup(group.id.uuidString) {
                            let updated = apiGroup.toGroup()
                            await MainActor.run {
                                if let idx = appState.groups.firstIndex(where: { $0.id == group.id }) {
                                    appState.groups[idx] = updated
                                    appState.saveGroupsLocal()
                                    appState.objectWillChange.send()
                                }
                            }
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 14))
                        Text(L10n.t("start") + " (\(group.members.count) \(L10n.t("players_needed")))")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.green)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)
            }

            // Invite code
            VStack(spacing: 12) {
                Text(L10n.t("invite_code"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textFaint).tracking(1.6)
                Text(group.code)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Theme.text).tracking(4)
                Button(action: { UIPasteboard.general.string = group.code }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc").font(.system(size: 14))
                        Text(L10n.t("copy_code"))
                    }
                    .font(.system(size: 14)).foregroundColor(Theme.textMuted)
                    .padding(.vertical, 10).padding(.horizontal, 18)
                    .liquidGlass(cornerRadius: 10)
                }
            }
            .padding(.horizontal, 24)

            // Rules
            rulesSection
                .padding(.top, 12)
        }
    }

    // MARK: - Invite Friends (pending only)

    private var inviteFriendsSection: some View {
        let memberUids = Set(group.members.map { $0.uid })
        let inviteable = friendManager.friends.filter { !memberUids.contains($0.id) }

        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("invite_friends"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textFaint).tracking(1.6)
                .padding(.horizontal, 24)

            if inviteable.isEmpty {
                Text(L10n.t("no_friends"))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(inviteable.enumerated()), id: \.element.id) { i, friend in
                        HStack(spacing: 12) {
                            AvatarView(name: friend.firstName, size: 36, color: Theme.textMuted,
                                       uid: friend.id, isMe: false)
                                .environmentObject(appState)
                            Text(friend.firstName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Theme.text)
                            Spacer()
                            if invitedIds.contains(friend.id) {
                                Text(L10n.t("invited_check"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.green)
                            } else {
                                Button(action: {
                                    Task { try? await APIClient.shared.sendInvitation(groupID: group.id.uuidString, toID: friend.id) }
                                    invitedIds.insert(friend.id)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.badge.plus").font(.system(size: 13))
                                        Text(L10n.t("invite_btn")).font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(Theme.textMuted)
                                    .padding(.vertical, 7).padding(.horizontal, 12)
                                    .liquidGlass(cornerRadius: 10)
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if i < inviteable.count - 1 {
                            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 56)
                        }
                    }
                }
                .liquidGlass(cornerRadius: 12)
                .padding(.horizontal, 24)
            }
        }
    }

    private func syncAgoText(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "sync \(L10n.t("just_now"))" }
        if seconds < 3600 { return "sync \(seconds / 60)min ago" }
        if seconds < 86400 { return "sync \(seconds / 3600)h ago" }
        return "sync \(seconds / 86400)d ago"
    }

    private func ruleRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(Theme.textMuted)
                .lineSpacing(3)
        }
    }
}
