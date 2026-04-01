import SwiftUI
import PhotosUI

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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
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
        .padding(.horizontal, 20)
        .padding(.top, 52)
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
            .onChange(of: selectedPhoto) { newItem in
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
                        .onChange(of: newUsername) { v in
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

    var socialGoalMinutes: Int { Int(socialGoalHours * 60) }

    @State private var showStreakInfo = false

    var goalSection: some View {
        VStack(spacing: 20) {
            // Total screen time — fixed 3h
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showStreakInfo.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen time")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.text)
                        Text("3h daily limit")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                    }
                    Spacer()
                    Text("3h00")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            // Social media — fixed 2h
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showStreakInfo.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Social media")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.text)
                        Text("2h daily limit")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                    }
                    Spacer()
                    Text("2h00")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Streak explanation
            if showStreakInfo {
                Text("Stay under the limit for several consecutive days to start a streak. The longer your streak, the better.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgWarm)
                    .cornerRadius(10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                            .onChange(of: notificationsOn) { on in
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
            .liquidGlass(cornerRadius: 14)
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
