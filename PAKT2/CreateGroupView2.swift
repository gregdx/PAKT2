import SwiftUI

struct CreateGroupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var step        = 0
    @State private var name        = ""
    @State private var mode        : GameMode          = .competitive
    @State private var scope       : ChallengeScope    = .total
    @State private var selectedApps: Set<String>       = []
    @State private var goalHours   : Double            = 2.0
    @State private var duration    : ChallengeDuration = .oneMonth
    @State private var stake            : StakeOption = .forFun
    @State private var customStake      : String = ""
    @State private var requiredPlayers  : Int = 2
    @State private var createdCode = ""
    @State private var startNow    = true

    var goalMinutes: Int { Int(goalHours * 60) }
    private static let wakingMinutesPerDay = kWakingMinutesPerDay
    var goalWakingPct: Int { Int((Double(goalMinutes) / Self.wakingMinutesPerDay) * 100) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch step {
            case 0:  nameAndModeStep
            case 1:  goalStep
            case 2:  stakeStep
            case 3:  playersStep
            case 4:  durationStep
            default: summaryStep
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Step 0: Name + mode

    var nameAndModeStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: L10n.t("new_group"), step: 0)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.t("group_name_label"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textFaint).tracking(1.6)

                        TextField("", text: $name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.text)
                            .onChange(of: name) { v in if v.count > 30 { name = String(v.prefix(30)) } }
                            .placeholder(when: name.isEmpty) {
                                Text("The Sober Crew")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(Theme.textFaint)
                            }
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.t("game_mode"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textFaint).tracking(1.6)

                        ForEach(GameMode.allCases, id: \.self) { m in
                            modeCard(m)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.t("tracked_time"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textFaint).tracking(1.6)

                        scopeCard(.total,
                                  title: L10n.t("scope_total"),
                                  desc: L10n.t("scope_total_desc"))
                        scopeCard(.social,
                                  title: L10n.t("scope_social"),
                                  desc: L10n.t("scope_social_desc"))
                        scopeCard(.apps,
                                  title: "Specific apps",
                                  desc: "Track only the apps you choose")

                        // App selection (visible when scope = .apps)
                        if scope == .apps {
                            appSelector
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 32)
            }
            PrimaryButton(label: L10n.t("continue")) { step = 1 }
                .padding(.horizontal, 28).padding(.bottom, 52)
                .opacity(name.isEmpty ? 0.35 : 1)
                .disabled(name.isEmpty)
        }
    }

    func modeCard(_ m: GameMode) -> some View {
        Button(action: { mode = m }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(mode == m ? Theme.text : Theme.border, lineWidth: 1.5).frame(width: 22, height: 22)
                    if mode == m { Circle().fill(Theme.text).frame(width: 10, height: 10) }
                }
                Text(m.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(mode == m ? Theme.text : Theme.textMuted)
                Spacer()
            }
            .padding(18)
            .liquidGlass(cornerRadius: 14)
            .opacity(mode == m ? 1.0 : 0.7)
        }
    }

    func scopeCard(_ s: ChallengeScope, title: String, desc: String) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { scope = s } }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(scope == s ? Theme.text : Theme.border, lineWidth: 1.5).frame(width: 22, height: 22)
                    if scope == s { Circle().fill(Theme.text).frame(width: 10, height: 10) }
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(scope == s ? Theme.text : Theme.textMuted)
                Spacer()
            }
            .padding(18)
            .liquidGlass(cornerRadius: 14)
            .opacity(scope == s ? 1.0 : 0.7)
        }
    }

    // MARK: - Step 1: Goal

    var goalStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: L10n.t("daily_goal"), step: 1)
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text(formatTime(goalMinutes))
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(L10n.t("per_day_max"))
                        .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                }

                VStack(spacing: 10) {
                    Slider(value: $goalHours, in: 0.5...6, step: 0.5)
                        .accentColor(Theme.text).padding(.horizontal, 28)
                    HStack {
                        Text("30 min").font(.system(size: 14)).foregroundColor(Theme.textFaint)
                        Spacer()
                        Text("6h").font(.system(size: 14)).foregroundColor(Theme.textFaint)
                    }
                    .padding(.horizontal, 28)
                }
            }
            Spacer()
            PrimaryButton(label: L10n.t("continue")) { step = 2 }
                .padding(.horizontal, 28).padding(.bottom, 52)
        }
    }

    // MARK: - Step 2: Stake

    var stakeStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: L10n.t("stake_title"), step: 2)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(StakeOption.allCases.filter { $0 != .custom }, id: \.self) { option in
                        Button(action: { stake = option }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle().stroke(stake == option ? Theme.text : Theme.border, lineWidth: 1.5).frame(width: 20, height: 20)
                                    if stake == option { Circle().fill(Theme.text).frame(width: 9, height: 9) }
                                }
                                Text(option.displayName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(stake == option ? Theme.text : Theme.textMuted)
                                Spacer()
                            }
                            .padding(18)
                            .liquidGlass(cornerRadius: 14)
                            .opacity(stake == option ? 1.0 : 0.7)
                        }
                    }

                    // Custom option
                    Button(action: { stake = .custom }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle().stroke(stake == .custom ? Theme.text : Theme.border, lineWidth: 1.5).frame(width: 20, height: 20)
                                if stake == .custom { Circle().fill(Theme.text).frame(width: 9, height: 9) }
                            }
                            Text(StakeOption.custom.displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(stake == .custom ? Theme.text : Theme.textMuted)
                            Spacer()
                        }
                        .padding(18)
                        .liquidGlass(cornerRadius: 14)
                        .opacity(stake == .custom ? 1.0 : 0.7)
                    }

                    if stake == .custom {
                        TextField(L10n.t("stake_custom_placeholder"), text: $customStake)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.text)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
            Spacer()
            PrimaryButton(label: L10n.t("continue")) { step = 3 }
                .padding(.horizontal, 28).padding(.bottom, 52)
                .opacity(stake == .custom && customStake.isEmpty ? 0.35 : 1)
                .disabled(stake == .custom && customStake.isEmpty)
        }
    }

    // MARK: - Step 3: Required Players

    var playersStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: L10n.t("required_players_title"), step: 3)
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("\(requiredPlayers)")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(L10n.t("players_needed"))
                        .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                }

                HStack(spacing: 24) {
                    Button(action: { if requiredPlayers > 2 { requiredPlayers -= 1 } }) {
                        Image(systemName: "minus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(requiredPlayers > 2 ? Theme.text : Theme.textFaint)
                            .frame(width: 48, height: 48)
                            .liquidGlass(cornerRadius: 12)
                    }
                    .disabled(requiredPlayers <= 2)

                    Button(action: { if requiredPlayers < 20 { requiredPlayers += 1 } }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.text)
                            .frame(width: 48, height: 48)
                            .liquidGlass(cornerRadius: 12)
                    }
                }
            }
            Spacer()
            PrimaryButton(label: L10n.t("continue")) { step = 4 }
                .padding(.horizontal, 28).padding(.bottom, 52)
        }
    }

    // MARK: - Step 4: Duration

    var durationStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: L10n.t("challenge_duration"), step: 4)
            Spacer()
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    ForEach(ChallengeDuration.allCases, id: \.self) { d in
                        durationCard(d)
                    }
                }

                // Start time option
                VStack(alignment: .leading, spacing: 12) {
                    Text("START TIME")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textFaint).tracking(1.6)

                    HStack(spacing: 10) {
                        Button(action: { startNow = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: startNow ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(startNow ? Theme.text : Theme.textFaint)
                                Text(L10n.t("start_now"))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(startNow ? Theme.text : Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .liquidGlass(cornerRadius: 12)
                            .opacity(startNow ? 1.0 : 0.6)
                        }

                        Button(action: { startNow = false }) {
                            HStack(spacing: 8) {
                                Image(systemName: !startNow ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(!startNow ? Theme.text : Theme.textFaint)
                                Text("At 00:00")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(!startNow ? Theme.text : Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .liquidGlass(cornerRadius: 12)
                            .opacity(!startNow ? 1.0 : 0.6)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            PrimaryButton(label: L10n.t("create_group_btn")) { createGroup() }
                .padding(.horizontal, 28).padding(.bottom, 52)
        }
    }

    func durationCard(_ d: ChallengeDuration) -> some View {
        Button(action: { duration = d }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(duration == d ? Theme.text : Theme.border, lineWidth: 1.5).frame(width: 22, height: 22)
                    if duration == d { Circle().fill(Theme.text).frame(width: 10, height: 10) }
                }
                Text(d.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(duration == d ? Theme.text : Theme.textMuted)
                Spacer()
                Text("\(d.days)j")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(18)
            .liquidGlass(cornerRadius: 14)
            .opacity(duration == d ? 1.0 : 0.7)
        }
    }

    // MARK: - Step 5: Summary

    var summaryStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 32) {
                VStack(spacing: 10) {
                    Text("✓")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(Theme.green)
                    Text(name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(L10n.t("pakt_created"))
                        .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                }

                VStack(spacing: 0) {
                    summaryRow(L10n.t("mode_label"), mode.displayName)
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    summaryRow(L10n.t("tracked_label"), scope == .social ? L10n.t("scope_social") : (scope == .apps ? selectedApps.sorted().joined(separator: ", ") : L10n.t("scope_total")))
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    summaryRow(L10n.t("goal"), formatTime(goalMinutes) + " / " + L10n.t("day"))
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    summaryRow(L10n.t("stake_label"), stake == .custom ? customStake : stake.displayName)
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    summaryRow(L10n.t("required_players"), "\(requiredPlayers) \(L10n.t("players_needed"))")
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    summaryRow(L10n.t("duration"), duration.displayName)
                }
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    Text(L10n.t("invite_code"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textFaint).tracking(1.6)
                    Text(createdCode)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Theme.text).tracking(4)
                    Text(L10n.t("copied") + " ✓")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.green)
                    Button(action: { UIPasteboard.general.string = createdCode }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc").font(.system(size: 14))
                            Text(L10n.t("copy_code"))
                        }
                        .font(.system(size: 15)).foregroundColor(Theme.textMuted)
                        .padding(.vertical, 10).padding(.horizontal, 18)
                        .liquidGlass(cornerRadius: 10)
                    }
                }
            }
            Spacer()
            PrimaryButton(label: L10n.t("view_my_group")) { dismiss() }
                .padding(.horizontal, 28).padding(.bottom, 52)
        }
    }

    // MARK: - Helpers

    func createGroup() {
        let code = generateGroupCode()
        createdCode = code
        UIPasteboard.general.string = code
        let stakeValue = stake == .custom ? customStake : stake.rawValue
        let start: Date = startNow ? Date() : Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        Log.d("[GROUP] Creating group: startNow=\(startNow) startDate=\(start) hasStarted=\(Date() >= start)")
        let newGroup = Group(
            name:        name,
            code:        code,
            mode:        mode,
            scope:       scope,
            goalMinutes: goalMinutes,
            duration:    duration,
            startDate:   start,
            members: [
                Member(
                    uid:          appState.currentUID,
                    name:         appState.userName,
                    todayMinutes: ScreenTimeManager.shared.readTodayMinutes(),
                    weekMinutes:  0,
                    monthMinutes: 0,
                    history:      []
                )
            ],
            creatorId: AuthManager.shared.currentUser?.id ?? "",
            stake: stakeValue,
            requiredPlayers: requiredPlayers,
            status: .pending,
            trackedApps: scope == .apps ? Array(selectedApps) : []
        )
        appState.addGroup(newGroup)
        step = 5
    }

    func stepHeader(title: String, step: Int) -> some View {
        HStack {
            Button(action: { if step == 0 { dismiss() } else { self.step -= 1 } }) {
                Image(systemName: step == 0 ? "xmark" : "chevron.left")
                    .font(.system(size: 18)).foregroundColor(Theme.textMuted)
            }
            Spacer()
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.textMuted)
            Spacer()
            Image(systemName: "xmark").opacity(0).font(.system(size: 18))
        }
        .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 28)
    }

    func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundColor(Theme.textMuted)
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }

    // MARK: - App Selector (for scope = .apps)

    private var appSelector: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AppDef.all) { app in
                    let isSelected = selectedApps.contains(app.id)
                    VStack(spacing: 6) {
                        AppIconView(app: app, size: 40)
                        Text(app.name)
                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? Theme.text : Theme.textFaint)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isSelected ? Theme.text.opacity(0.08) : Color.clear)
                    .liquidGlass(cornerRadius: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Theme.text.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
                    .opacity(isSelected ? 1.0 : 0.6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isSelected { selectedApps.remove(app.id) } else { selectedApps.insert(app.id) }
                        }
                    }
                }
            }

            if !selectedApps.isEmpty {
                Text("\(selectedApps.count) app\(selectedApps.count > 1 ? "s" : "") selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }
}
