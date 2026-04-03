import SwiftUI
import DeviceActivity

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var stManager = ScreenTimeManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunch  = true
    @State private var selectedTab = 2

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
        .id("\(isDarkMode)_\(appLanguage)")
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
                Task {
                    let ok = await AuthManager.shared.refreshTokens()
                    if ok {
                        AuthManager.shared.refreshExtensionToken()
                        WebSocketManager.shared.connect()
                    }
                }
                startPeriodicSync()
            } else if phase == .background {
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

    var mainApp: some View {
        ZStack(alignment: .bottom) {
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
                }

                TabView(selection: $selectedTab) {
                    ActivitiesView().environmentObject(appState)
                        .tag(0)
                    GroupsListView(selectedTab: $selectedTab).environmentObject(appState)
                        .tag(1)
                    TodayView().environmentObject(appState)
                        .tag(2)
                    NearYouView().environmentObject(appState)
                        .tag(3)
                    ProfileView().environmentObject(appState)
                        .tag(4)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: selectedTab)
            }

            HStack {
                Spacer()
                tabIcon("bubble.left.and.bubble.right", index: 0)
                Spacer()
                tabIcon("person.2",    index: 1)
                Spacer()
                tabIcon("sun.max",     index: 2)
                Spacer()
                tabIcon("mappin.and.ellipse", index: 3)
                Spacer()
                tabIcon("person",      index: 4)
                Spacer()
            }
            .padding(.vertical, 14).padding(.bottom, 20)
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .onPreferenceChange(TodayMinutesKey.self) { minutes in
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

    func tabIcon(_ icon: String, index: Int) -> some View {
        let labels = ["Messages", "Groups", "Today", "Near you", "Profile"]
        let isSelected = selectedTab == index
        return Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            VStack(spacing: 5) {
                if index == 4 {
                    // Profile tab — show user photo
                    if let img = appState.profileUIImage {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(isSelected ? Theme.text : Color.clear, lineWidth: 1.5))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? Theme.text : Theme.textFaint)
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? Theme.text : Theme.textFaint)
                }
                Circle()
                    .fill(isSelected ? Theme.text : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel(labels[index])
    }
}

// MARK: - Launch

struct LaunchView: View {
    @State private var opacity = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("PAKT")
                .font(.system(size: 76, weight: .bold, design: .default))
                .foregroundColor(.white)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.7)) { opacity = 1.0 }
                }
        }
    }
}
