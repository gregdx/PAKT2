import SwiftUI
import PhotosUI
import FamilyControls
import DeviceActivity
import ManagedSettings

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    @State private var goalHours: Double = 3.0
    @State private var socialGoalHours: Double = 1.0
    @State private var goalSaved = false
    @State private var newUsername: String = ""
    @State private var usernameState: UsernameState = .idle
    @State private var checkTask: Task<Void, Never>? = nil
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var showDeleteConfirm = false
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("notificationsOn") private var notificationsOn = true
    @ObservedObject private var stManager = ScreenTimeManager.shared

    var goalMinutes: Int { Int(goalHours * 60) }
    var goalWakingPct: Int { Int((Double(goalMinutes) / kWakingMinutesPerDay) * 100) }

    enum UsernameState {
        case idle, checking, available, taken, saved, error(String)
        var color: Color {
            switch self {
            case .available, .saved: return Theme.green
            case .taken, .error:     return Theme.red
            default:                 return Theme.textFaint
            }
        }
        var message: String {
            switch self {
            case .idle:         return ""
            case .checking:     return L10n.t("checking")
            case .available:    return L10n.t("available")
            case .taken:        return L10n.t("already_taken")
            case .saved:        return L10n.t("saved")
            case .error(let m): return m
            }
        }
    }

    @State private var appeared = false
    @State private var showFamilyPicker = false
    @State private var showTrackedAppsPicker = false
    @State private var trackedAppsDraft: FamilyActivitySelection = ScreenTimeManager.loadTrackedAppsSelection()
    @State private var showAutoDetect = false
    @State private var autoDetectStatus: String = ""
    @State private var debugLines: [String] = []
    @State private var runningDebug = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        profileCard
                        settingsGroup(title: L10n.t("daily_st_goal")) { goalSection }
                        settingsGroup(title: L10n.t("preferences")) { preferencesSection }
                        settingsGroup(title: L10n.t("account")) { accountSection }
                        settingsGroup(title: L10n.t("support")) { supportSection }
                        signOutButton
                        deleteAccountButton
                        versionLabel
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            goalHours = appState.goalHours
            socialGoalHours = appState.socialGoalHours
            newUsername = appState.userName
        }
        .confirmationDialog(L10n.t("delete_account"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L10n.t("confirm_delete"), role: .destructive) {
                Task {
                    try? await AuthManager.shared.deleteAccount()
                    await MainActor.run { appState.signOut() }
                }
            }
            Button(L10n.t("pause_account")) {
                Task {
                    try? await AuthManager.shared.pauseAccount()
                    await MainActor.run { appState.signOut() }
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("delete_account_warn"))
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36)
                    .liquidGlass(cornerRadius: 18)
            }
            Spacer()
            Text(L10n.t("settings"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 24)
    }

    // MARK: - Profile card

    var profileCard: some View {
        VStack(spacing: 16) {
            // Photo
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    if let uiImage = appState.profileUIImage {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(width: 80, height: 80).clipShape(Circle())
                    } else {
                        Circle().fill(Theme.bgWarm).frame(width: 80, height: 80)
                        Text(String(appState.userName.prefix(1)).uppercased())
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                    }
                    Circle().fill(Theme.text).frame(width: 24, height: 24)
                        .overlay(Image(systemName: "camera").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.bg))
                        .offset(x: 28, y: 28)
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { appState.saveImage(img) }
                    }
                }
            }

            // Name + email
            VStack(spacing: 4) {
                Text(appState.userName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.text)
                if let email = AuthManager.shared.currentUser?.email {
                    Text(email)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textFaint)
                }
            }

            // Username
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("@")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.textFaint)
                    TextField("", text: $newUsername)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.text)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: newUsername) { _, v in
                            let clean = v.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            if clean == appState.userName.lowercased() {
                                usernameState = .idle; return
                            }
                            usernameState = .checking
                            checkTask?.cancel()
                            checkTask = Task {
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                guard !Task.isCancelled else { return }
                                if clean.count < 2 { await MainActor.run { usernameState = .idle }; return }
                                let available = await AuthManager.shared.isUsernameAvailable(clean)
                                await MainActor.run { usernameState = available ? .available : .taken }
                            }
                        }
                    if case .available = usernameState {
                        Button(action: {
                            Task {
                                let ok = await appState.updateUsername(newUsername)
                                await MainActor.run { usernameState = ok ? .saved : .error("error") }
                            }
                        }) {
                            Text(L10n.t("save"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.bg)
                                .padding(.vertical, 5).padding(.horizontal, 12)
                                .background(Theme.text)
                                .cornerRadius(6)
                        }
                    }
                }
                if !usernameState.message.isEmpty {
                    Text(usernameState.message)
                        .font(.system(size: 13))
                        .foregroundColor(usernameState.color)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Goal section

    var goalSection: some View {
        VStack(spacing: 20) {
            // Screen time goal
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.t("scope_total"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(formatTime(Int(goalHours * 60)))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                }
                Slider(value: $goalHours, in: 0.5...8.0, step: 0.5)
                    .tint(Theme.green)
                Text("\(Int(goalHours * 60.0 / kWakingMinutesPerDay * 100))% \(L10n.t("waking_pct"))")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
            }

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            // Social media goal
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.t("on_social_media"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(formatTime(Int(socialGoalHours * 60)))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                }
                Slider(value: $socialGoalHours, in: 0.5...5.0, step: 0.5)
                    .tint(Theme.blue)
            }

            // Save button
            if goalHours != appState.goalHours || socialGoalHours != appState.socialGoalHours {
                Button(action: {
                    Task {
                        await AuthManager.shared.updateGoal(hours: goalHours)
                        appState.updateGoalHours(goalHours)
                        appState.updateSocialGoalHours(socialGoalHours)
                        goalSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { goalSaved = false }
                    }
                }) {
                    Text(goalSaved ? L10n.t("saved") : L10n.t("save_goal"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(goalSaved ? Theme.green : Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .liquidGlass(cornerRadius: 12)
                }
            }
        }
    }

    // MARK: - Tracked apps (per-app DAM tracking, Opal-style "top apps" source)

    var trackedAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .foregroundColor(Theme.green)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps à suivre en détail")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text)
                    Text("\(stManager.trackedAppsTokens.count)/\(ScreenTimeManager.MAX_TRACKED_APPS) apps sélectionnées")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                Button {
                    trackedAppsDraft = stManager.trackedAppsSelection
                    showTrackedAppsPicker = true
                } label: {
                    Text("Choisir")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.green)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 4)


            if !stManager.trackedAppsTokens.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(stManager.trackedAppsTokens.enumerated()), id: \.offset) { _, token in
                        HStack(spacing: 10) {
                            Label(token).labelStyle(.iconOnly).frame(width: 24, height: 24)
                            Label(token).labelStyle(.titleOnly)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
        .familyActivityPicker(isPresented: $showTrackedAppsPicker, selection: $trackedAppsDraft)
        .onChange(of: showTrackedAppsPicker) { _, isPresented in
            if !isPresented {
                stManager.saveTrackedAppsSelection(trackedAppsDraft)
            }
        }
    }

    // MARK: - Apps Tracked (FamilyActivitySelection)

    var appsTrackedSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "apps.iphone")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stManager.hasFamilySelection ? "Tracking enabled" : "Not tracking")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text)
                    Text(stManager.hasFamilySelection
                        ? "\(stManager.familySelection.applicationTokens.count) apps, \(stManager.familySelection.categoryTokens.count) categories"
                        : "Pick apps to track your screen time")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
            }

            Button(action: { showFamilyPicker = true }) {
                Text(stManager.hasFamilySelection ? "Change apps" : "Select apps to track")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .liquidGlass(cornerRadius: 12)
            }

            Text("Tip: tap « All Apps & Categories » at the top of the picker to track your full screen time.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .familyActivityPicker(isPresented: $showFamilyPicker, selection: Binding(
            get: { stManager.familySelection },
            set: { newSelection in
                stManager.saveFamilySelection(newSelection)
            }
        ))
    }

    // MARK: - Debug / Force Sync

    var debugSection: some View {
        VStack(spacing: 12) {
            Button(action: { runDebugCheck() }) {
                HStack(spacing: 8) {
                    if runningDebug {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(runningDebug ? "Running..." : "Force Sync + Debug")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlass(cornerRadius: 12)
            }
            .disabled(runningDebug)

            Button(action: { resetLocalScreenTimeCache() }) {
                Text("Reset local cache")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Button(action: { wipeBackendToday() }) {
                Text("Wipe backend today (force 0)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Button(action: { simulateYesterdayRollover() }) {
                Text("Simulate yesterday rollover (240min)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            if !debugLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(debugLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.hasPrefix("✓") ? "✓" : (line.hasPrefix("✗") ? "✗" : "•"))
                                .foregroundColor(line.hasPrefix("✓") ? Theme.green : (line.hasPrefix("✗") ? Theme.red : Theme.textMuted))
                                .font(.system(size: 12, weight: .bold))
                            Text(line.hasPrefix("✓") || line.hasPrefix("✗") ? String(line.dropFirst(2)) : line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .liquidGlass(cornerRadius: 10)
            }
        }
    }

    private func resetLocalScreenTimeCache() {
        // UserDefaults standard
        UserDefaults.standard.removeObject(forKey: UDKey.todayMinutes)
        UserDefaults.standard.removeObject(forKey: UDKey.todayDate)
        UserDefaults.standard.removeObject(forKey: UDKey.catSocial)
        UserDefaults.standard.removeObject(forKey: UDKey.catSocialDate)
        // App Group
        let ag = UserDefaults(suiteName: "group.com.PAKT2")
        ag?.removeObject(forKey: "shared_today")
        ag?.removeObject(forKey: "shared_today_date")
        ag?.removeObject(forKey: "shared_social")
        ag?.removeObject(forKey: "shared_social_date")
        ag?.synchronize()
        // Keychain — this is where the Monitor extension writes
        deleteKeychain(key: "shared_today")
        deleteKeychain(key: "shared_today_date")
        deleteKeychain(key: "shared_social")
        deleteKeychain(key: "shared_social_date")
        deleteKeychain(key: "dar_debug")
        stManager.profileToday = 0
        stManager.categorySocial = 0
        stManager.updateLocalGroups(appState: appState)
        // Restart monitoring with fresh state
        stManager.startBackgroundMonitoring()
        debugLines = ["✓ Local cache reset (UD + AppGroup + Keychain)"]
    }

    /// Simule un rollover de minuit : écrit shared_history avec hier=240min
    /// et déclenche un loadProfileCache pour drainer vers historyRaw.
    /// Vérifie la barre "hier" dans le weekChart après tap.
    private func simulateYesterdayRollover() {
        let cal = Calendar.current
        let df = ScreenTimeManager.dateFormatter
        let yesterday = df.string(from: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let ag = UserDefaults(suiteName: "group.com.PAKT2")
        let existing = ag?.string(forKey: "shared_history") ?? ""
        var byDate: [String: Int] = [:]
        for entry in existing.split(separator: ",") {
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let m = Int(parts[1]) else { continue }
            byDate[String(parts[0])] = m
        }
        byDate[yesterday] = 240
        let raw = byDate.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        ag?.set(raw, forKey: "shared_history")
        ag?.synchronize()
        stManager.loadProfileCache()
        debugLines = ["✓ Wrote shared_history: \(yesterday)=240", "✓ Triggered loadProfileCache"]
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: "9U5UZW39LQ.com.PAKT2"
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Force-wipes today's score on the backend via /scores/correct (direct
    /// assign, bypasses GREATEST). Use this to unpoison a stale inflated
    /// value previously written by the broken Monitor extension. After wiping,
    /// the next DAR render (release build only) will repopulate correctly.
    private func wipeBackendToday() {
        let today = ScreenTimeManager.dateFormatter.string(from: Date())
        debugLines = ["• Wiping backend today score for \(today)..."]
        Task {
            do {
                try await APIClient.shared.correctScore(minutes: 0, socialMinutes: 0, date: today)
                await MainActor.run {
                    stManager.profileToday = 0
                    stManager.categorySocial = 0
                    stManager.updateLocalGroups(appState: appState)
                    debugLines = ["✓ Backend today wiped to 0 for \(today)"]
                }
            } catch {
                await MainActor.run {
                    debugLines = ["✗ Wipe failed: \(error.localizedDescription)"]
                }
            }
        }
    }

    private func runDebugCheck() {
        runningDebug = true
        debugLines = []
        Task {
            await MainActor.run {
                debugLines.append("— Starting debug —")
            }

            // 1. Family Activity Selection
            await MainActor.run {
                if stManager.hasFamilySelection {
                    debugLines.append("✓ Family selection: \(stManager.familySelection.applicationTokens.count) apps, \(stManager.familySelection.categoryTokens.count) cats")
                } else {
                    debugLines.append("✗ NO family selection — pick apps first")
                }
            }

            // 2. Profile today value
            await MainActor.run {
                debugLines.append("• profileToday = \(stManager.profileToday) min")
                debugLines.append("• categorySocial = \(stManager.categorySocial) min")
                debugLines.append("• profileHistory count = \(stManager.profileHistory.count)")
                if let last = stManager.profileHistory.last {
                    debugLines.append("• profileHistory last = \(last.date): \(last.minutes) min")
                }
                // Check if today's date is in history
                let todayKey = ScreenTimeManager.dateFormatter.string(from: Date())
                if let todayInHistory = stManager.profileHistory.first(where: { $0.date == todayKey }) {
                    debugLines.append("✓ HistoryKey has today: \(todayInHistory.minutes) min")
                } else {
                    debugLines.append("✗ HistoryKey does NOT have today")
                }
            }

            // 3. Keychain extension token
            let hasToken = AuthManager.shared.extensionToken != nil
            await MainActor.run {
                if hasToken {
                    debugLines.append("✓ Extension token present")
                } else {
                    debugLines.append("✗ NO extension token in Keychain")
                }
            }

            // 4. Access token
            let hasAccess = APIClient.shared.accessToken != nil
            await MainActor.run {
                if hasAccess {
                    debugLines.append("✓ Access token present")
                } else {
                    debugLines.append("✗ NO access token")
                }
            }

            // 5. Try manual POST with current profileToday
            let testMinutes = stManager.profileToday
            if testMinutes > 0 {
                do {
                    let todayStr = ScreenTimeManager.dateFormatter.string(from: Date())
                    try await APIClient.shared.syncScore(minutes: testMinutes, socialMinutes: nil, date: todayStr)
                    await MainActor.run {
                        debugLines.append("✓ POST /scores/sync OK with \(testMinutes) min")
                    }
                } catch {
                    await MainActor.run {
                        debugLines.append("✗ POST FAILED: \(error.localizedDescription)")
                    }
                }
            } else {
                await MainActor.run {
                    debugLines.append("✗ profileToday = 0, nothing to sync")
                }
            }

            // 6. Refresh groups from backend
            await appState.refreshGroupsOnly()
            await MainActor.run {
                debugLines.append("• Groups refreshed from backend")
                let uid = appState.currentUID
                for group in appState.groups.filter({ !$0.isDemo }) {
                    if let me = group.members.first(where: { $0.uid == uid }) {
                        debugLines.append("  \(group.name): my today = \(me.todayMinutes) min")
                    }
                }
            }

            // 7. Restart monitoring
            stManager.startBackgroundMonitoring()
            await MainActor.run {
                debugLines.append("• Background monitoring restarted")
                debugLines.append("— Done —")
                runningDebug = false
            }
        }
    }

    // MARK: - Preferences

    var preferencesSection: some View {
        VStack(spacing: 0) {
            // Screen time status
            Button {
                if !stManager.isAuthorized {
                    // D'abord essayer via le code, sinon ouvrir les réglages iOS
                    stManager.pendingAuthRequest = true
                    dismiss()
                }
            } label: {
                settingsRow(
                    icon: "iphone",
                    label: L10n.t("screen_time_status"),
                    trailing: {
                        AnyView(
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(stManager.isAuthorized ? Theme.green : Theme.red)
                                    .frame(width: 7, height: 7)
                                Text(stManager.isAuthorized ? L10n.t("connected") : L10n.t("not_connected"))
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textMuted)
                            }
                        )
                    }
                )
            }
            .buttonStyle(PlainButtonStyle())

            if !stManager.isAuthorized {
                Button {
                    if let url = URL(string: "App-prefs:SCREEN_TIME") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12))
                        Text(L10n.t("open_screen_time_settings"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Theme.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            if let err = stManager.authError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            rowDivider

            // Notifications
            settingsRow(
                icon: "bell",
                label: L10n.t("notifications"),
                trailing: {
                    AnyView(
                        Toggle("", isOn: $notificationsOn)
                            .labelsHidden()
                            .tint(Theme.green)
                            .onChange(of: notificationsOn) { _, on in
                                if on { NotificationService.shared.scheduleDailyReminder() }
                                else  { NotificationService.shared.cancelDailyReminder() }
                            }
                    )
                }
            )

            rowDivider

            // Dark mode
            settingsRow(
                icon: "moon",
                label: L10n.t("dark_mode"),
                trailing: {
                    AnyView(
                        Toggle("", isOn: $isDarkMode)
                            .labelsHidden()
                            .tint(Theme.green)
                    )
                }
            )

        }
    }

    @State private var calibrationPct: Double = ScreenTimeManager.calibrationFactor * 100

    private var calibrationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(Theme.green)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration Screen Time")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text)
                    Text("Corrige la surestimation d'Apple DAM")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                Text("\(Int(calibrationPct))%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.green)
            }
            Slider(value: $calibrationPct, in: 30...100, step: 1)
                .tint(Theme.green)
                .onChange(of: calibrationPct) { _, newValue in
                    ScreenTimeManager.setCalibrationFactor(newValue / 100)
                    ScreenTimeManager.shared.loadProfileCache()
                }
        }
        .padding(.vertical, 10)
    }

    // Language picker removed — English only for now

    // MARK: - Account

    var accountSection: some View {
        VStack(spacing: 0) {
            if let user = AuthManager.shared.currentUser {
                settingsRow(
                    icon: "envelope",
                    label: L10n.t("email"),
                    trailing: {
                        AnyView(
                            Text(user.email)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        )
                    }
                )
            }
        }
    }

    // MARK: - Support

    var supportSection: some View {
        VStack(spacing: 0) {
            Button(action: {
                if let url = URL(string: "https://pakt-app.com/privacy") { openURL(url) }
            }) {
                settingsRow(
                    icon: "hand.raised",
                    label: L10n.t("privacy_policy"),
                    trailing: {
                        AnyView(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textFaint)
                        )
                    }
                )
            }

            rowDivider

            Button(action: {
                if let url = URL(string: "mailto:support@pakt-app.com") { openURL(url) }
            }) {
                settingsRow(
                    icon: "envelope",
                    label: L10n.t("help_feedback"),
                    trailing: {
                        AnyView(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textFaint)
                        )
                    }
                )
            }
        }
    }

    // MARK: - Sign out

    var signOutButton: some View {
        Button(action: {
            AuthManager.shared.signOut()
            appState.signOut()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                Text(L10n.t("sign_out"))
                    .font(.system(size: 17, weight: .medium))
            }
            .foregroundColor(Theme.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .liquidGlass(cornerRadius: 16)
        }
    }

    // MARK: - Delete account

    var deleteAccountButton: some View {
        Button(action: { showDeleteConfirm = true }) {
            Text(L10n.t("delete_account"))
                .font(.system(size: 15))
                .foregroundColor(Theme.textFaint)
        }
    }

    // MARK: - Version

    var versionLabel: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return Text("PAKT v\(version) (\(build))")
            .font(.system(size: 13))
            .foregroundColor(Theme.textFaint)
            .padding(.top, 4)
            .padding(.bottom, 20)
    }

    // MARK: - Reusable components

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(1.2)
                .padding(.leading, 4)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .liquidGlass(cornerRadius: 16)
        }
    }

    private func settingsRow(icon: String, label: String, trailing: () -> AnyView) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.textMuted)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(Theme.text)
            Spacer()
            trailing()
        }
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.leading, 42)
    }
}
