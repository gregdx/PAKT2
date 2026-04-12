import SwiftUI
import DeviceActivity

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var stManager = ScreenTimeManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunch  = true
    @State private var selectedTab = 1

    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("appLanguage") private var appLanguage = "en"
    @State private var syncTimer: Timer? = nil

    var body: some View {
        ZStack {
            if showLaunch {
                LaunchView().transition(.opacity)
            } else if !appState.isOnboarded {
                OnboardingView().transition(.opacity).environmentObject(appState)
            } else {
                mainApp.transition(.opacity)
            }
        }
        .onReceive(AuthManager.shared.$currentUser) { user in
            guard let user, appState.isOnboarded else { return }
            Task {
                await appState.syncFromBackend()
                InvitationManager.shared.startListening()
                FriendManager.shared.startListening()
                NotificationService.shared.startListening()
                WebSocketManager.shared.connect()
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .environment(\.colorScheme, isDarkMode ? .dark : .light)
        .onAppear {
            PaktAnalytics.track(.appOpened)
            PaktAnalytics.sessionStart()
            applyInterfaceStyle(isDarkMode)
            appState.restoreLastSession()
            networkMonitor.start()
            if stManager.isAuthorized {
                stManager.startBackgroundMonitoring()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.5)) { showLaunch = false }
                if !stManager.isAuthorized {
                    Task { await stManager.requestAuthorization() }
                }
            }
        }
        .onChange(of: isDarkMode) { newValue in
            applyInterfaceStyle(newValue)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                stManager.refreshAuthorizationStatus()
                if stManager.isAuthorized {
                    stManager.startBackgroundMonitoring()
                } else {
                    // Auth perdue (ex: l'utilisateur a touché aux réglages Temps d'écran)
                    Task { await stManager.requestAuthorization() }
                }
                // Force read Keychain/AppGroup + POST to backend on foreground
                // The Monitor extension wrote fresh values while we were backgrounded.
                stManager.loadProfileCache()
                stManager.updateLocalGroups(appState: appState)
                stManager.syncToBackend(appState: appState)
                Task {
                    let ok = await AuthManager.shared.refreshTokens()
                    if ok {
                        AuthManager.shared.refreshExtensionToken()
                        WebSocketManager.shared.connect()
                    }
                }
                startPeriodicSync()
            } else if phase == .background {
                PaktAnalytics.sessionEnd()
                WebSocketManager.shared.disconnect()
                syncTimer?.invalidate()
                syncTimer = nil
            }
        }
    }

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

    // Global today filter used by the background DAR
    private var globalTodayFilter: DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Date())),
            devices: .init([.iPhone])
        )
    }

    var mainApp: some View {
        ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
            // Offline banner
            if !networkMonitor.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.system(size: 13))
                    Text(L10n.t("offline"))
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.red)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            SwiftUI.Group {
                switch selectedTab {
                case 0: NearYouView().environmentObject(appState)
                case 2: ProfileView().environmentObject(appState)
                default: GroupsListView(selectedTab: $selectedTab).environmentObject(appState)
                }
            }

            // Tab bar — fixed at bottom
            HStack(spacing: 0) {
                tabItem("mappin.and.ellipse", label: "Explore", index: 0)
                tabItem("person.2.fill", label: "Home", index: 1)

                // Profile tab avec photo
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 2 }
                    PaktAnalytics.track(.tabSwitched, properties: ["tab": "Profile"])
                }) {
                    VStack(spacing: 4) {
                        if let img = appState.profileUIImage {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(selectedTab == 2 ? Theme.text : Color.clear, lineWidth: 2))
                                .scaleEffect(selectedTab == 2 ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab == 2)
                        } else {
                            Circle()
                                .fill(Theme.bgWarm)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Text(String(appState.userName.prefix(1)).uppercased())
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(Theme.textMuted)
                                )
                                .overlay(Circle().stroke(selectedTab == 2 ? Theme.text : Color.clear, lineWidth: 2))
                                .scaleEffect(selectedTab == 2 ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab == 2)
                        }
                        Text("Profile")
                            .font(.system(size: 10, weight: selectedTab == 2 ? .semibold : .regular))
                            .foregroundColor(selectedTab == 2 ? Theme.text : Theme.textFaint)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Profile")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                Rectangle()
                    .fill(Theme.bg)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
            )
        }

        }
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
        .onPreferenceChange(TodayMinutesKey.self) { minutes in
            Log.d("[PAKT Content] TodayMinutesKey preference fired: \(minutes)")
            guard minutes > 0 else { return }
            let todayStr = ScreenTimeManager.dateFormatter.string(from: Date())
            UserDefaults.standard.set(minutes, forKey: UDKey.todayMinutes)
            UserDefaults.standard.set(todayStr, forKey: UDKey.todayDate)
            stManager.updateProfileToday(minutes)
            stManager.injectTodayIntoHistory(date: todayStr, minutes: minutes)
            stManager.updateLocalGroups(appState: appState)
            stManager.syncToBackend(appState: appState)
        }
        .onPreferenceChange(SocialMinutesKey.self) { social in
            guard social > 0 else { return }
            stManager.updateCategorySocial(social)
            stManager.updateLocalGroups(appState: appState)
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
        }
        .onAppear {
            AppIconCache.shared.preloadAll()
            startPeriodicSync()
            Task {
                let granted = await NotificationService.shared.requestPermission()
                Log.d("[Notif] Permission granted: \(granted)")
            }

            // Refresh token THEN start everything
            Task {
                if AuthManager.shared.accessToken != nil {
                    _ = await AuthManager.shared.refreshTokens()
                }

                guard AuthManager.shared.accessToken != nil else { return }

                InvitationManager.shared.startListening()
                FriendManager.shared.startListening()
                NotificationService.shared.startListening()
                await appState.syncFromBackend()

                WebSocketManager.shared.connect()
                WebSocketManager.shared.subscribe("scores")
                WebSocketManager.shared.subscribe("friends")
                WebSocketManager.shared.subscribe("requests")
                WebSocketManager.shared.subscribe("invitations")
                WebSocketManager.shared.subscribe("chat")
                if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
                    WebSocketManager.shared.subscribe("pending:\(deviceId)")
                }
                for group in appState.groups {
                    WebSocketManager.shared.subscribe("group:\(group.id.uuidString)")
                }
            }
        }
    }

    private func applyInterfaceStyle(_ dark: Bool) {
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            ws.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }

    private func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            let minutes = ScreenTimeManager.shared.profileToday
            let social = ScreenTimeManager.shared.categorySocial
            if minutes > 0 {
                let date = ScreenTimeManager.dateFormatter.string(from: Date())
                Task { try? await APIClient.shared.syncScore(minutes: minutes, socialMinutes: social > 0 ? social : nil, date: date) }
            }
        }
    }

    func tabItem(_ icon: String, label: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
            PaktAnalytics.track(.tabSwitched, properties: ["tab": label])
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.text : Theme.textFaint)
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.text : Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
    }
    
}

// MARK: - Launch

struct LaunchView: View {
    @State private var opacity = 0.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Text("PAKT")
                .font(.system(size: 84, weight: .black, design: .default))
                .foregroundColor(.white)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 1.0
            }
        }
    }
}
