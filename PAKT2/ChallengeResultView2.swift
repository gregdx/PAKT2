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
    @State private var currentSlide    = 0

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

    // MARK: - Slide gradients

    private let slideGradients: [[Color]] = [
        [Color(red: 0.10, green: 0.08, blue: 0.25), Color(red: 0.22, green: 0.10, blue: 0.45)],   // Intro - deep purple
        [Color(red: 0.05, green: 0.20, blue: 0.15), Color(red: 0.08, green: 0.35, blue: 0.22)],   // Winner - deep green
        [Color(red: 0.12, green: 0.10, blue: 0.28), Color(red: 0.20, green: 0.14, blue: 0.40)],   // Ranking - violet
        [Color(red: 0.05, green: 0.15, blue: 0.30), Color(red: 0.08, green: 0.28, blue: 0.50)],   // Best day - deep blue
        [Color(red: 0.30, green: 0.08, blue: 0.08), Color(red: 0.45, green: 0.12, blue: 0.10)],   // Worst day - deep red
        [Color(red: 0.18, green: 0.12, blue: 0.05), Color(red: 0.35, green: 0.22, blue: 0.08)],   // Group stats - amber
        [Color(red: 0.08, green: 0.08, blue: 0.22), Color(red: 0.15, green: 0.12, blue: 0.35)],   // Play again - indigo
    ]

    var body: some View {
        ZStack {
            if restarted {
                Theme.bg.ignoresSafeArea()
                restartedConfirmation
            } else {
                // Gradient background that transitions with slide
                slideBackground
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: currentSlide)

                VStack(spacing: 0) {
                    // Top bar: close + progress dots
                    topBar
                        .padding(.top, 8)

                    // Paged slides
                    TabView(selection: $currentSlide) {
                        slideIntro.tag(0)
                        slideWinnerOrResult.tag(1)
                        slideRanking.tag(2)
                        slideBestDay.tag(3)
                        slideWorstDay.tag(4)
                        slideGroupStats.tag(5)
                        slidePlayAgain.tag(6)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
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

    // MARK: - Background

    private var slideBackground: some View {
        let colors = slideGradients[min(currentSlide, slideGradients.count - 1)]
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            Spacer()

            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(i == currentSlide ? Color.white : Color.white.opacity(0.45))
                        .frame(width: i == currentSlide ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentSlide)
                }
            }

            Spacer()

            // Invisible balance
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Slide 1: Intro

    private var slideIntro: some View {
        WrappedSlide {
            Spacer()

            Text(isSuccess ? "🏆" : "🏁")
                .font(.system(size: 80))
                .scaleEffect(appeared ? 1.0 : 0.3)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: appeared)

            Text(group.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .tracking(2)
                .textCase(.uppercase)
                .padding(.top, 16)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.4), value: appeared)

            Text(isSuccess ? "CHALLENGE\nCOMPLETE" : "CHALLENGE\nFAILED")
                .font(.system(size: 46, weight: .black))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)
                .scaleEffect(appeared ? 1.0 : 0.8)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.5), value: appeared)

            // Duration badge
            Text("\(group.duration.days) days")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .tracking(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
                .padding(.top, 24)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: appeared)

            Spacer()
            Spacer()

            swipeHint
        }
    }

    // MARK: - Slide 2: Winner / Result

    private var slideWinnerOrResult: some View {
        WrappedSlide {
            if group.mode == .competitive, let w = winner {
                Spacer()

                SlideAppearWrapper(delay: 0.1) {
                    Text("THE WINNER")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(Theme.green)
                        .tracking(4)
                }

                SlideAppearWrapper(delay: 0.25) {
                    AvatarView(name: w.name, size: 110,
                               color: Theme.green,
                               uid: w.uid, isMe: appState.isMe(w))
                        .environmentObject(appState)
                        .overlay(
                            Circle()
                                .stroke(Theme.green.opacity(0.5), lineWidth: 4)
                        )
                        .shadow(color: Theme.green.opacity(0.3), radius: 20, x: 0, y: 0)
                        .padding(.top, 20)
                }

                SlideAppearWrapper(delay: 0.4) {
                    Text(w.name)
                        .font(.system(size: 38, weight: .black))
                        .foregroundColor(.white)
                        .padding(.top, 16)
                }

                let mins = group.rankMinutes(w)
                if mins > 0 {
                    SlideAppearWrapper(delay: 0.55) {
                        Text(formatTime(mins))
                            .font(.system(size: 56, weight: .black))
                            .foregroundColor(Theme.green)
                            .padding(.top, 8)

                        Text("average per day")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 4)
                    }
                }

                Spacer()
                Spacer()
            } else {
                // Collective result
                Spacer()

                SlideAppearWrapper(delay: 0.1) {
                    Text(isSuccess ? "🎉" : "😤")
                        .font(.system(size: 72))
                }

                SlideAppearWrapper(delay: 0.3) {
                    Text(isSuccess ? "GOAL\nREACHED" : "GOAL\nNOT REACHED")
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 16)
                }

                SlideAppearWrapper(delay: 0.5) {
                    Text(isSuccess ? "Your group crushed it." : "Better luck next time.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 12)
                }

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - Slide 3: Full Ranking

    private var slideRanking: some View {
        WrappedSlide {
            Spacer().frame(height: 20)

            SlideAppearWrapper(delay: 0.1) {
                Text("FINAL RANKING")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(4)
            }

            Spacer().frame(height: 24)

            VStack(spacing: 0) {
                ForEach(Array(group.rankedMembers.enumerated()), id: \.offset) { i, member in
                    let rank  = i + 1
                    let color = memberColor(rank: rank, total: group.rankedMembers.count, mode: group.mode)
                    let mins  = group.rankMinutes(member)

                    SlideAppearWrapper(delay: 0.15 + Double(i) * 0.08) {
                        HStack(spacing: 14) {
                            // Rank badge
                            ZStack {
                                Circle()
                                    .fill(rank == 1 ? Theme.green.opacity(0.2) : Color.white.opacity(0.08))
                                    .frame(width: 36, height: 36)
                                Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "#\(rank)")
                                    .font(rank <= 3 ? .system(size: 18) : .system(size: 14, weight: .bold))
                                    .foregroundColor(rank <= 3 ? .white : .white.opacity(0.6))
                            }

                            AvatarView(name: member.name, size: 42, color: color,
                                       uid: member.uid, isMe: appState.isMe(member))
                                .environmentObject(appState)

                            Text(member.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            Text(mins > 0 ? formatTime(mins) + "/d" : "--")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(color)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 18)
                    }

                    if i < group.rankedMembers.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 4)

            Spacer()
        }
    }

    // MARK: - Slide 4: Best Day

    private var slideBestDay: some View {
        WrappedSlide {
            if let best = bestDayMember {
                Spacer()

                SlideAppearWrapper(delay: 0.1) {
                    Text("BEST DAY")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(4)
                }

                SlideAppearWrapper(delay: 0.2) {
                    Text("Least screen time\nin a single day")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                SlideAppearWrapper(delay: 0.35) {
                    AvatarView(name: best.member.name, size: 80,
                               color: Theme.green,
                               uid: best.member.uid, isMe: appState.isMe(best.member))
                        .environmentObject(appState)
                        .overlay(Circle().stroke(Theme.green.opacity(0.4), lineWidth: 3))
                        .padding(.top, 24)
                }

                SlideAppearWrapper(delay: 0.5) {
                    Text(best.member.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 14)
                }

                SlideAppearWrapper(delay: 0.65) {
                    Text(formatTime(best.minutes))
                        .font(.system(size: 64, weight: .black))
                        .foregroundColor(Theme.green)
                        .padding(.top, 8)

                    Text("screen time")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 2)
                }

                Spacer()
                Spacer()
            } else {
                Spacer()
                Text("No data recorded")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    // MARK: - Slide 5: Worst Day

    private var slideWorstDay: some View {
        WrappedSlide {
            if let worst = worstDayMember {
                Spacer()

                SlideAppearWrapper(delay: 0.1) {
                    Text("WORST DAY")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(4)
                }

                SlideAppearWrapper(delay: 0.2) {
                    Text("Most screen time\nin a single day")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                SlideAppearWrapper(delay: 0.35) {
                    AvatarView(name: worst.member.name, size: 80,
                               color: Theme.red,
                               uid: worst.member.uid, isMe: appState.isMe(worst.member))
                        .environmentObject(appState)
                        .overlay(Circle().stroke(Theme.red.opacity(0.4), lineWidth: 3))
                        .padding(.top, 24)
                }

                SlideAppearWrapper(delay: 0.5) {
                    Text(worst.member.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 14)
                }

                SlideAppearWrapper(delay: 0.65) {
                    Text(formatTime(worst.minutes))
                        .font(.system(size: 64, weight: .black))
                        .foregroundColor(Theme.red)
                        .padding(.top, 8)

                    Text("screen time")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 2)
                }

                Spacer()
                Spacer()
            } else {
                Spacer()
                Text("No data recorded")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    // MARK: - Slide 6: Group Stats

    private var slideGroupStats: some View {
        WrappedSlide {
            Spacer()

            SlideAppearWrapper(delay: 0.1) {
                Text("YOUR GROUP")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(4)
            }

            SlideAppearWrapper(delay: 0.2) {
                Text("in numbers")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)
            }

            Spacer().frame(height: 40)

            VStack(spacing: 16) {
                SlideAppearWrapper(delay: 0.3) {
                    statCard(
                        number: "\(group.members.count)",
                        label: "PLAYERS",
                        accent: Theme.green
                    )
                }

                SlideAppearWrapper(delay: 0.4) {
                    statCard(
                        number: "\(group.duration.days)",
                        label: "DAYS",
                        accent: Theme.orange
                    )
                }

                SlideAppearWrapper(delay: 0.5) {
                    statCard(
                        number: formatTime(group.goalMinutes),
                        label: "DAILY GOAL",
                        accent: Color.white
                    )
                }

                if groupAvg > 0 {
                    SlideAppearWrapper(delay: 0.6) {
                        statCard(
                            number: formatTime(groupAvg),
                            label: "GROUP AVERAGE",
                            accent: groupAvg <= group.goalMinutes ? Theme.green : Theme.red
                        )
                    }
                }
            }
            .padding(.horizontal, 4)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 7: Play Again

    private var slidePlayAgain: some View {
        WrappedSlide {
            Spacer()

            SlideAppearWrapper(delay: 0.1) {
                Text("🔥")
                    .font(.system(size: 60))
            }

            SlideAppearWrapper(delay: 0.25) {
                Text("READY FOR\nANOTHER ONE?")
                    .font(.system(size: 38, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 12)
            }

            SlideAppearWrapper(delay: 0.4) {
                Text("Same group, new challenge.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)
            }

            Spacer().frame(height: 48)

            SlideAppearWrapper(delay: 0.55) {
                VStack(spacing: 14) {
                    Button(action: {
                        restartHarder = false
                        newGroupName = suggestedName
                        showRenameSheet = true
                    }) {
                        Text("Restart same challenge")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: {
                        restartHarder = true
                        newGroupName = suggestedName
                        showRenameSheet = true
                    }) {
                        Text("Harder goal (\(formatTime(harderGoal))/day)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func statCard(number: String, label: String, accent: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(number)
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(accent)
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(2)
            }
            Spacer()
        }
        .padding(20)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var swipeHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
            Text("Swipe to explore")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.bottom, 32)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(1.0), value: appeared)
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

// MARK: - Wrapped Slide Container

private struct WrappedSlide<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }
}

// MARK: - Slide Appear Wrapper (scale + opacity on appear)

private struct SlideAppearWrapper<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: Content
    @State private var visible = false

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .scaleEffect(visible ? 1.0 : 0.85)
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(delay)) {
                visible = true
            }
        }
        .onDisappear {
            visible = false
        }
    }
}
