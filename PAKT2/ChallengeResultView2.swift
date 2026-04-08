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
    @State private var pulseAnimation = false
    @State private var cardOffsets: [CGSize] = Array(repeating: .zero, count: 7)
    @State private var cardRotations: [Double] = Array(repeating: 0, count: 7)
    @State private var dismissedCards: Set<Int> = []
    @State private var topCardIndex: Int = 0

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
                if peak > (worst?.1 ?? 0) { worst = (m, peak) }
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
                if low < (best?.1 ?? Int.max) { best = (m, low) }
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

    private var allCards: [AnyView] {
        [
            AnyView(cardIntro),
            AnyView(cardWinner),
            AnyView(cardRanking),
            AnyView(cardBestDay),
            AnyView(cardWorstDay),
            AnyView(cardGroupStats),
            AnyView(cardPlayAgain),
        ]
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if restarted {
                restartedConfirmation
            } else {
                VStack(spacing: 0) {
                    // Top bar
                    cardTopBar
                        .padding(.top, 56)

                    // Card stack
                    ZStack {
                        ForEach((0..<7).reversed(), id: \.self) { i in
                            if !dismissedCards.contains(i) {
                                let isTop = i == topCardIndex
                                allCards[i]
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(Color.white.opacity(0.5))
                                    )
                                    .liquidGlass(cornerRadius: 24, style: .ultraThin)
                                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
                                    .padding(.horizontal, 20)
                                    .scaleEffect(isTop ? 1.0 : max(0.9, 1.0 - Double(i - topCardIndex) * 0.04))
                                    .offset(y: isTop ? 0 : CGFloat(i - topCardIndex) * 8)
                                    .offset(cardOffsets[i])
                                    .rotationEffect(.degrees(cardRotations[i]))
                                    .zIndex(Double(7 - i))
                                    .gesture(isTop ? cardDragGesture(for: i) : nil)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: cardOffsets[i])
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showRenameSheet) { renameSheet }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { appeared = true }
        }
        .task {
            guard !medalAwarded, let w = winner, !w.uid.isEmpty else { return }
            medalAwarded = true
        }
    }

    // MARK: - Card drag gesture

    private func cardDragGesture(for index: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in
                cardOffsets[index] = value.translation
                cardRotations[index] = Double(value.translation.width) / 20.0
            }
            .onEnded { value in
                let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                if distance > 120 {
                    // Throw the card away
                    let throwMultiplier: CGFloat = 3.0
                    withAnimation(.easeOut(duration: 0.4)) {
                        cardOffsets[index] = CGSize(
                            width: value.translation.width * throwMultiplier,
                            height: value.translation.height * throwMultiplier
                        )
                        cardRotations[index] = Double(value.translation.width) / 8.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismissedCards.insert(index)
                        // After dismissing, find next non-dismissed card
                        let next = (index + 1..<7).first { !dismissedCards.contains($0) }
                        if let next { topCardIndex = next }
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        cardOffsets[index] = .zero
                        cardRotations[index] = 0
                    }
                }
            }
    }

    // MARK: - Top bar

    private var cardTopBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }

            Spacer()

            // Counter
            Text("\(topCardIndex + 1) / 7")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textFaint)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Card contents

    private var cardIntro: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isSuccess ? "trophy.fill" : "flag.checkered")
                .font(.system(size: 48))
                .foregroundColor(isSuccess ? Theme.green : Theme.textMuted)
            Text(group.name.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(2)
            Text(isSuccess ? "CHALLENGE\nCOMPLETE" : "CHALLENGE\nFAILED")
                .font(.system(size: 40, weight: .black))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Text("\(group.duration.days) days")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(Theme.bgWarm))
            Spacer()
            swipeHint
        }
    }

    private var cardWinner: some View {
        VStack(spacing: 16) {
            Spacer()
            if group.mode == .competitive, let w = winner {
                Text(L10n.t("the_winner")).font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.green).tracking(4)
                AvatarView(name: w.name, size: 100, color: Theme.green, uid: w.uid, isMe: appState.isMe(w))
                    .environmentObject(appState)
                    .overlay(Circle().stroke(Theme.green.opacity(0.4), lineWidth: 3))
                Text(w.name).font(.system(size: 34, weight: .black)).foregroundColor(Theme.text)
                let mins = group.rankMinutes(w)
                if mins > 0 {
                    Text(formatTime(mins)).font(.system(size: 48, weight: .black)).foregroundColor(Theme.green)
                    Text(L10n.t("avg_per_day")).font(.system(size: 15)).foregroundColor(Theme.textFaint)
                }
            } else {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 48)).foregroundColor(isSuccess ? Theme.green : Theme.red)
                Text(L10n.t(isSuccess ? "goal_reached_title" : "goal_not_reached_title"))
                    .font(.system(size: 36, weight: .black)).foregroundColor(Theme.text).multilineTextAlignment(.center)
                Text(L10n.t(isSuccess ? "group_crushed_it" : "better_luck"))
                    .font(.system(size: 16)).foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
    }

    private var cardRanking: some View {
        VStack(spacing: 0) {
            Text(L10n.t("final_ranking_title"))
                .font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(4)
                .padding(.top, 24).padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(group.rankedMembers.enumerated()), id: \.offset) { i, member in
                    let rank = i + 1
                    let color = memberColor(rank: rank, total: group.rankedMembers.count, mode: group.mode)
                    let mins = group.rankMinutes(member)
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(rank == 1 ? Theme.green.opacity(0.15) : Theme.bgWarm).frame(width: 36, height: 36)
                            if rank == 1 {
                                Image(systemName: "trophy.fill").font(.system(size: 15)).foregroundColor(Theme.green)
                            } else if rank <= 3 {
                                Image(systemName: "medal.fill").font(.system(size: 14)).foregroundColor(Theme.textMuted)
                            } else {
                                Text("#\(rank)").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.textMuted)
                            }
                        }
                        AvatarView(name: member.name, size: 40, color: color, uid: member.uid, isMe: appState.isMe(member))
                            .environmentObject(appState)
                        Text(member.name).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text).lineLimit(1)
                        Spacer()
                        Text(mins > 0 ? formatTime(mins) : "--").font(.system(size: 20, weight: .black)).foregroundColor(rank == 1 ? Theme.green : Theme.text)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    if i < group.rankedMembers.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 66)
                    }
                }
            }
            Spacer()
        }
    }

    private var cardBestDay: some View {
        VStack(spacing: 16) {
            Spacer()
            if let best = bestDayMember {
                Text(L10n.t("best_day")).font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(4)
                Text(L10n.t("least_st_day")).font(.system(size: 17)).foregroundColor(Theme.textMuted).multilineTextAlignment(.center)
                AvatarView(name: best.member.name, size: 72, color: Theme.green, uid: best.member.uid, isMe: appState.isMe(best.member))
                    .environmentObject(appState)
                    .overlay(Circle().stroke(Theme.green.opacity(0.3), lineWidth: 3))
                Text(best.member.name).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                Text(formatTime(best.minutes)).font(.system(size: 56, weight: .black)).foregroundColor(Theme.green)
                Text(L10n.t("screen_time_label")).font(.system(size: 15)).foregroundColor(Theme.textFaint)
            } else {
                Text(L10n.t("no_data_recorded")).font(.system(size: 17)).foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
    }

    private var cardWorstDay: some View {
        VStack(spacing: 16) {
            Spacer()
            if let worst = worstDayMember {
                Text(L10n.t("worst_day")).font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(4)
                Text(L10n.t("most_st_day")).font(.system(size: 17)).foregroundColor(Theme.textMuted).multilineTextAlignment(.center)
                AvatarView(name: worst.member.name, size: 72, color: Theme.red, uid: worst.member.uid, isMe: appState.isMe(worst.member))
                    .environmentObject(appState)
                    .overlay(Circle().stroke(Theme.red.opacity(0.3), lineWidth: 3))
                Text(worst.member.name).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                Text(formatTime(worst.minutes)).font(.system(size: 56, weight: .black)).foregroundColor(Theme.red)
                Text(L10n.t("screen_time_label")).font(.system(size: 15)).foregroundColor(Theme.textFaint)
            } else {
                Text(L10n.t("no_data_recorded")).font(.system(size: 17)).foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
    }

    private var cardGroupStats: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(L10n.t("your_group")).font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(4)
            Text(L10n.t("in_numbers")).font(.system(size: 17)).foregroundColor(Theme.textMuted)
            Spacer().frame(height: 16)
            cardStatRow(number: "\(group.members.count)", label: L10n.t("players"), accent: Theme.green)
            cardStatRow(number: "\(group.duration.days)", label: L10n.t("days_label"), accent: Theme.orange)
            cardStatRow(number: formatTime(group.goalMinutes), label: L10n.t("daily_goal_label"), accent: Theme.text)
            if groupAvg > 0 {
                cardStatRow(number: formatTime(groupAvg), label: L10n.t("group_average"), accent: groupAvg <= group.goalMinutes ? Theme.green : Theme.red)
            }
            Spacer()
        }
    }

    private var cardPlayAgain: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "flame.fill").font(.system(size: 44)).foregroundColor(Theme.orange)
            Text(L10n.t("ready_another"))
                .font(.system(size: 32, weight: .black)).foregroundColor(Theme.text)
                .multilineTextAlignment(.center).lineSpacing(4)
            Text(L10n.t("same_group_new")).font(.system(size: 16)).foregroundColor(Theme.textMuted)
            Spacer().frame(height: 32)
            Button(action: { restartHarder = false; newGroupName = suggestedName; showRenameSheet = true }) {
                Text(L10n.t("restart_challenge"))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.text).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Button(action: { restartHarder = true; newGroupName = suggestedName; showRenameSheet = true }) {
                Text("\(L10n.t("harder_goal")) (\(formatTime(harderGoal))/day)")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.clear).liquidGlass(cornerRadius: 14))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func cardStatRow(number: String, label: String, accent: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(number).font(.system(size: 32, weight: .black)).foregroundColor(accent)
                Text(label).font(.system(size: 12, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(2)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bgWarm))
    }

    private var swipeHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "hand.draw").font(.system(size: 18)).foregroundColor(Theme.textFaint)
            Text(L10n.t("swipe_to_explore")).font(.system(size: 13)).foregroundColor(Theme.textFaint)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Restart confirmed

    var restartedConfirmation: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(Theme.green)
                Text(L10n.t("new_challenge_started"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.text)
                Text(newGroupName)
                    .font(.system(size: 17))
                    .foregroundColor(Theme.textFaint)
            }
            Spacer()
            PrimaryButton(label: L10n.t("lets_go")) { dismiss() }
                .padding(.horizontal, 24).padding(.bottom, 52)
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
                    Text(L10n.t("name_challenge")).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.textMuted)
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

                PrimaryButton(label: L10n.t("start")) {
                    showRenameSheet = false
                    createRestartGroup(harder: restartHarder, name: newGroupName)
                }
                .padding(.horizontal, 24).padding(.bottom, 52)
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


