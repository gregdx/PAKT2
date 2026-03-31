import SwiftUI

struct ChallengeResultView: View {
    let group: Group
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var showRenameSheet = false
    @State private var restarted       = false
    @State private var restartHarder   = false
    @State private var newGroupName    = ""
    @State private var medalAwarded    = false
    @State private var appeared        = false

    var winner   : Member? { group.rankedMembers.first }
    var loser    : Member? { group.rankedMembers.last  }
    var isSuccess: Bool    { group.collectiveGoalReached }
    var harderGoal: Int    { max(30, group.goalMinutes - 30) }

    var suggestedName: String {
        let base = group.name
        let existing = appState.groups.map { $0.name }
        var n = 2; var candidate = "\(base) \(n)"
        while existing.contains(candidate) { n += 1; candidate = "\(base) \(n)" }
        return candidate
    }

    // MARK: - Computed stats

    /// Member with the worst single day (most screen time in one day)
    var worstDayMember: (member: Member, minutes: Int)? {
        var worst: (Member, Int)? = nil
        for m in group.members {
            if let peak = m.history.map(\.minutes).max(), peak > 0 {
                if worst == nil || peak > worst!.1 { worst = (m, peak) }
            }
        }
        return worst.map { (member: $0.0, minutes: $0.1) }
    }

    /// Member with the best single day (least screen time in one day, > 0)
    var bestDayMember: (member: Member, minutes: Int)? {
        var best: (Member, Int)? = nil
        for m in group.members {
            let valid = m.history.map(\.minutes).filter { $0 > 0 }
            if let low = valid.min() {
                if best == nil || low < best!.1 { best = (m, low) }
            }
        }
        return best.map { (member: $0.0, minutes: $0.1) }
    }

    /// Group average daily screen time
    var groupAvg: Int {
        let all = group.members.compactMap { m -> Int? in
            let mins = group.rankMinutes(m)
            return mins > 0 ? mins : nil
        }
        guard !all.isEmpty else { return 0 }
        return all.reduce(0, +) / all.count
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if restarted {
                restartedConfirmation
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Close
                        HStack {
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Theme.textFaint)
                                    .frame(width: 36, height: 36)
                                    .liquidGlass(cornerRadius: 10)
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 24)

                        // Result header
                        resultHeader
                            .padding(.top, 16)

                        // Ranking
                        rankingSection
                            .padding(.top, 28)

                        // Stats highlights
                        statsSection
                            .padding(.top, 20)

                        // Restart
                        Rectangle().fill(Theme.separator).frame(height: 0.5)
                            .padding(.horizontal, 24).padding(.vertical, 28)
                        restartSection.padding(.horizontal, 24)

                        Spacer().frame(height: 60)
                    }
                }
            }
        }
        .sheet(isPresented: $showRenameSheet) { renameSheet }
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.1)) { appeared = true } }
        .task {
            guard !medalAwarded, let w = winner, !w.uid.isEmpty else { return }
            medalAwarded = true
            let medal = Medal(
                groupName: group.name,
                date: Date(),
                mode: group.mode.rawValue,
                avgMinutes: group.rankMinutes(w),
                goalMinutes: group.goalMinutes
            )
            // TODO: implement awardMedal via API
        }
    }

    // MARK: - Result header

    var resultHeader: some View {
        VStack(spacing: 20) {
            if group.mode == .competitive, let w = winner {
                // Winner
                AvatarView(name: w.name, size: 72,
                           color: Theme.green,
                           uid: w.uid, isMe: appState.isMe(w))
                    .environmentObject(appState)
                    .overlay(Circle().stroke(Theme.green.opacity(0.3), lineWidth: 3))
                    .scaleEffect(appeared ? 1.0 : 0.6)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text(w.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("Winner")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.green)
                        .tracking(1.2)
                        .textCase(.uppercase)
                }

                let mins = group.rankMinutes(w)
                if mins > 0 {
                    Text(formatTime(mins) + " / day")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.green)
                }
            } else {
                // Collective
                VStack(spacing: 6) {
                    Text(isSuccess ? "Challenge complete" : "Challenge failed")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(isSuccess ? "Goal reached" : "Goal not reached")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isSuccess ? Theme.green : Theme.red)
                        .tracking(1.2)
                        .textCase(.uppercase)
                }
            }

            // Summary pills
            HStack(spacing: 10) {
                infoPill(title: "\(group.members.count)", subtitle: "players")
                infoPill(title: "\(group.duration.days)d", subtitle: "duration")
                infoPill(title: formatTime(group.goalMinutes), subtitle: "goal")
                if groupAvg > 0 {
                    infoPill(title: formatTime(groupAvg), subtitle: "avg")
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, 24)
    }

    func infoPill(title: String, subtitle: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.text)
            Text(subtitle.uppercased())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textFaint)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Ranking

    var rankingSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(group.rankedMembers.enumerated()), id: \.offset) { i, member in
                let rank  = i + 1
                let color = memberColor(rank: rank, total: group.rankedMembers.count, mode: group.mode)
                let mins  = group.rankMinutes(member)
                let isWinner = rank == 1
                let underGoal = mins > 0 && mins <= group.goalMinutes

                HStack(spacing: 12) {
                    Text(rank <= 3 ? ["1st", "2nd", "3rd"][rank - 1] : "\(rank)th")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isWinner ? Theme.green : Theme.textFaint)
                        .frame(width: 34, alignment: .leading)

                    AvatarView(name: member.name, size: 38, color: color,
                               uid: member.uid, isMe: appState.isMe(member))
                        .environmentObject(appState)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.text)
                        if underGoal {
                            Text("Under goal")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.green)
                        }
                    }

                    Spacer()

                    Text(mins > 0 ? formatTime(mins) + "/d" : "--")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(color)
                }
                .padding(.vertical, 12).padding(.horizontal, 18)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .animation(.easeOut(duration: 0.35).delay(Double(i) * 0.06 + 0.2), value: appeared)

                if i < group.rankedMembers.count - 1 {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 18)
                }
            }
        }
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
    }

    // MARK: - Stats highlights

    var statsSection: some View {
        VStack(spacing: 8) {
            if let worst = worstDayMember {
                statRow(
                    icon: "arrow.up.right",
                    iconColor: Theme.red,
                    label: "Most screen time in a day",
                    value: formatTime(worst.minutes),
                    name: worst.member.name
                )
            }
            if let best = bestDayMember {
                statRow(
                    icon: "arrow.down.right",
                    iconColor: Theme.green,
                    label: "Least screen time in a day",
                    value: formatTime(best.minutes),
                    name: best.member.name
                )
            }
        }
        .padding(.horizontal, 24)
    }

    func statRow(icon: String, iconColor: Color, label: String, value: String, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .liquidGlass(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(iconColor)
                }
            }
            Spacer()
        }
        .padding(16)
        .liquidGlass(cornerRadius: 12)
    }

    // MARK: - Restart section

    var restartSection: some View {
        VStack(spacing: 12) {
            PrimaryButton(label: "Restart same challenge") {
                restartHarder = false
                newGroupName = suggestedName
                showRenameSheet = true
            }

            Button(action: {
                restartHarder = true
                newGroupName = suggestedName
                showRenameSheet = true
            }) {
                Text("Harder goal (\(formatTime(harderGoal))/day)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .liquidGlass(cornerRadius: 12)
            }
        }
    }

    // MARK: - Restart confirmed

    var restartedConfirmation: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(Theme.green)
                Text("New challenge started")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.text)
                Text(newGroupName)
                    .font(.system(size: 17))
                    .foregroundColor(Theme.textFaint)
            }
            Spacer()
            PrimaryButton(label: "Let's go") { dismiss() }
                .padding(.horizontal, 28).padding(.bottom, 52)
        }
    }

    // MARK: - Rename sheet

    var renameSheet: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { showRenameSheet = false }) {
                        Image(systemName: "xmark").font(.system(size: 18)).foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text("Name the new challenge").font(.system(size: 16, weight: .medium)).foregroundColor(Theme.textMuted)
                    Spacer()
                    Image(systemName: "xmark").opacity(0).font(.system(size: 18))
                }
                .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 40)

                Spacer()

                VStack(spacing: 10) {
                    TextField("", text: $newGroupName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 40)
                }
                .padding(.horizontal, 32)

                Spacer()

                PrimaryButton(label: "Start") {
                    showRenameSheet = false
                    createRestartGroup(harder: restartHarder, name: newGroupName)
                }
                .padding(.horizontal, 28).padding(.bottom, 52)
                .opacity(newGroupName.isEmpty ? 0.35 : 1)
                .disabled(newGroupName.isEmpty)
            }
        }
    }

    // MARK: - Create restart group

    func createRestartGroup(harder: Bool, name: String) {
        let newGoal = harder ? harderGoal : group.goalMinutes
        let resetMembers = group.members.map { member in
            Member(name: member.name, todayMinutes: 0, weekMinutes: 0, monthMinutes: 0,
                   history: makeFakeHistory(newGoal - 10))
        }
        let newGroup = Group(
            name: name, code: generateGroupCode(), mode: group.mode,
            goalMinutes: newGoal, duration: group.duration, startDate: Date(),
            members: resetMembers, creatorId: group.creatorId
        )
        appState.addGroup(newGroup)
        withAnimation { restarted = true }
    }
}
