import SwiftUI
import DeviceActivity
import Network

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
            print("[PAKT] currentUser loaded: \(user.id) — triggering sync")
            Task {
                await appState.syncFromBackend()
                print("[PAKT] Auth-triggered sync done. Groups: \(appState.groups.count)")
                InvitationManager.shared.startListening()
                FriendManager.shared.startListening()
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
                // Demander l'autorisation si pas encore fait (requis pour que les extensions fonctionnent)
                // Ne pas redemander si déjà autorisé (évite de perturber les réglages Screen Time)
                if !stManager.isAuthorized {
                    Task { await stManager.requestAuthorization() }
                } else {
                    stManager.startBackgroundMonitoring()
                }
            }
        }
        .onChange(of: isDarkMode) { newValue in
            applyInterfaceStyle(newValue)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                darRefreshID += 1
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

    @State private var darRefreshID = 0

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
                    GroupsListView(selectedTab: $selectedTab).environmentObject(appState)
                        .tag(0)
                    ActivitiesView().environmentObject(appState)
                        .tag(1)
                    TodayView().environmentObject(appState)
                        .tag(2)
                    ProfileView(isVisible: selectedTab == 3).environmentObject(appState)
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: selectedTab)
            }

            HStack {
                Spacer()
                tabIcon("person.2",    index: 0)
                Spacer()
                tabIcon("figure.walk", index: 1)
                Spacer()
                tabIcon("sun.max",     index: 2)
                Spacer()
                tabIcon("person",      index: 3)
                Spacer()
            }
            .padding(.vertical, 14).padding(.bottom, 20)
            .background(
                Theme.bg.opacity(0.85)
                    .overlay(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            AppIconCache.shared.preloadAll()
            print("[PAKT] stManager.isAuthorized = \(stManager.isAuthorized)")
            print("[PAKT] profileToday = \(stManager.profileToday)")
        }
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
            startPeriodicSync()
            Task { _ = await NotificationService.shared.requestPermission() }

            // Refresh token THEN start everything
            Task {
                let hasToken = AuthManager.shared.accessToken != nil
                print("[PAKT] Has token before refresh: \(hasToken)")

                if hasToken {
                    let refreshed = await AuthManager.shared.refreshTokens()
                    print("[PAKT] Token refresh: \(refreshed)")
                } else {
                    print("[PAKT] No token yet — skipping refresh (fresh sign in?)")
                }

                guard AuthManager.shared.accessToken != nil else {
                    print("[PAKT] No valid token — skipping network init")
                    return
                }

                print("[PAKT] Starting network init...")
                InvitationManager.shared.startListening()
                FriendManager.shared.startListening()

                print("[PAKT] Syncing from backend...")
                await appState.syncFromBackend()
                print("[PAKT] Sync done. Groups: \(appState.groups.count)")

                WebSocketManager.shared.connect()
                WebSocketManager.shared.subscribe("scores")
                WebSocketManager.shared.subscribe("friends")
                WebSocketManager.shared.subscribe("requests")
                WebSocketManager.shared.subscribe("invitations")
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
        let labels = ["Groups", "Activities", "Today", "Profile"]
        let isSelected = selectedTab == index
        return Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            VStack(spacing: 5) {
                if index == 3 {
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
