import SwiftUI

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
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    detailHeader

                    let _ = Log.d("[GROUP DETAIL] status=\(group.status) isPending=\(group.isPending) hasStarted=\(group.hasStarted) startDate=\(group.startDate) now=\(Date())")
                    if group.isPending {
                        pendingPaktView
                    } else if !group.hasStarted {
                        // Group is active but starts at midnight
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

                            // Members with -- scores
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
                            .liquidGlass(cornerRadius: 14)
                            .padding(.horizontal, 24)
                        }
                    } else if !isSyncing {
                        challengeBanner
                        periodPicker
                        rankingList
                        raceChart
                            .padding(.top, 24)
                        groupOverview
                            .padding(.top, 24)
                        challengeProgress
                            .padding(.top, 24)
                        rulesSection
                            .padding(.top, 24)
                    } else {
                        ProgressView()
                            .padding(.top, 60)
                    }

                    Spacer().frame(height: 100)
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
        .sheet(isPresented: $showGroupChat) {
            if groupOpt != nil {
                GroupChatView(group: group)
                    .environmentObject(appState)
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
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            .accessibilityLabel("Back")
            Spacer()
            Text(group.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
            Button(action: { showGroupChat = true }) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textMuted)
            }
            .accessibilityLabel("Group chat")
            Button(action: { showEdit = true }) {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textMuted)
            }
            .accessibilityLabel("Edit group")
        }
        .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 16)
    }

    @ViewBuilder
    private var challengeBanner: some View {
        if group.isCompleted {
            Button(action: { showResult = true }) {
                HStack(spacing: 12) {
                    Text("\u{1F3C1}")
                        .font(.system(size: 20))
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

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases, id: \.self) { p in
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { period = p } }) {
                    Text(p.displayName)
                        .font(.system(size: p == .total && period == .total ? 17 : 15, weight: period == p ? .bold : .regular))
                        .foregroundColor(period == p ? (p == .total ? Theme.orange : Theme.text) : Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(period == p ? (p == .total ? Theme.orange.opacity(0.08) : Theme.bgCard) : Color.clear)
                    .cornerRadius(10)
                }
            }
        }
        .padding(3)
        .liquidGlass(cornerRadius: 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Ranking List (minimal)

    private var rankingList: some View {
        VStack(spacing: 8) {
            if isSyncing {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.textFaint)
                    Text(L10n.t("loading")).font(.system(size: 14)).foregroundColor(Theme.textFaint)
                }
                .padding(.vertical, 10)
            }
            let sorted = group.members.sorted { minutesFor($0) < minutesFor($1) }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, member in
                let rank = i + 1
                let mins = minutesFor(member)
                let scoreColor: Color = mins == 0 ? Theme.textFaint : Theme.text
                let isLeader = period == .total && rank == 1 && mins > 0

                Button {
                    selectedMemberUID = member.uid
                } label: {
                    HStack(spacing: 16) {
                        // Rank badge
                        if isLeader {
                            Text("\u{1F3C6}")
                                .font(.system(size: 22))
                                .frame(width: 36)
                        } else if period == .total && rank == 2 && mins > 0 {
                            Text("\u{1F948}")
                                .font(.system(size: 20))
                                .frame(width: 36)
                        } else if period == .total && rank == 3 && mins > 0 {
                            Text("\u{1F949}")
                                .font(.system(size: 20))
                                .frame(width: 36)
                        } else {
                            Text("#\(rank)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Theme.textMuted)
                                .frame(width: 36, alignment: .leading)
                        }

                        AvatarView(name: member.name, size: 42, color: Theme.textMuted,
                                   uid: member.uid, isMe: appState.isMe(member))
                            .environmentObject(appState)

                        Text(member.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.text)

                        Spacer()

                        Text(mins > 0 ? formatTime(mins) : "--")
                            .font(.system(size: period == .total ? 24 : 20, weight: .bold))
                            .foregroundColor(scoreColor)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
                .background(isLeader && period == .total ? Theme.orange.opacity(0.08) : Color.clear)
                .liquidGlass(cornerRadius: 16)
                .overlay(
                    isLeader && period == .total ? RoundedRectangle(cornerRadius: 16).stroke(Theme.orange.opacity(0.4), lineWidth: 1.5) : nil
                )
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Member Profile Destination

    @ViewBuilder

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
            .liquidGlass(cornerRadius: 14)
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
                    Text("BEST")
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
                .liquidGlass(cornerRadius: 14)
            }

            // Under goal — avatars row
            if !underGoalMembers.isEmpty {
                VStack(spacing: 10) {
                    Text("UNDER GOAL")
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
                .liquidGlass(cornerRadius: 14)
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
                Text("goal: \(formatTime(group.goalMinutes))")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(16)
            .liquidGlass(cornerRadius: 14)
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
            .liquidGlass(cornerRadius: 14)
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
            .liquidGlass(cornerRadius: 14)
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
