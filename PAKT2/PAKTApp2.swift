import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct PAKTApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Log.d("[PAKT] onOpenURL: \(url)")

                    // Handle join links: pakt2://join/GRP-XXXX or https://pakt-app.com/join/GRP-XXXX
                    if url.host == "join" || url.path.hasPrefix("/join/") {
                        let code = url.lastPathComponent
                        if !code.isEmpty && code != "join" {
                            // Store the code to be picked up by GroupsListView
                            UserDefaults.standard.set(code, forKey: "pendingJoinCode")
                            NotificationCenter.default.post(name: .init("openJoinSheet"), object: code)
                        }
                        return
                    }

                    guard url.scheme == "pakt2",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

                    switch url.host {
                    case "screentime":
                        guard let minutesStr = components.queryItems?.first(where: { $0.name == "minutes" })?.value,
                              let minutes = Int(minutesStr), minutes > 0, minutes <= 1440 else { return }
                        let todayStr = ScreenTimeManager.dateFormatter.string(from: Date())
                        UserDefaults.standard.set(minutes, forKey: UDKey.todayMinutes)
                        UserDefaults.standard.set(todayStr, forKey: UDKey.todayDate)
                        ScreenTimeManager.shared.updateProfileToday(minutes)
                        // Accumuler dans l'historique pour le graphe (ne dépend plus du weekChart)
                        ScreenTimeManager.shared.injectTodayIntoHistory(date: todayStr, minutes: minutes)
                        // Mise à jour immédiate des groupes locaux
                        ScreenTimeManager.shared.updateLocalGroups(appState: AppState.shared)
                        let currentSocial = ScreenTimeManager.shared.categorySocial
                        Task { try? await APIClient.shared.syncScore(minutes: minutes, socialMinutes: currentSocial > 0 ? currentSocial : nil, date: todayStr) }

                    case "weekavg":
                        guard let minutesStr = components.queryItems?.first(where: { $0.name == "minutes" })?.value,
                              let minutes = Int(minutesStr), minutes > 0 else { return }
                        ScreenTimeManager.shared.updateProfileWeekAvg(minutes)

                    case "monthavg":
                        guard let minutesStr = components.queryItems?.first(where: { $0.name == "minutes" })?.value,
                              let minutes = Int(minutesStr), minutes > 0 else { return }
                        ScreenTimeManager.shared.updateProfileMonthAvg(minutes)

                    case "categories":
                        if let s = components.queryItems?.first(where: { $0.name == "social" })?.value,
                           let v = Int(s), v > 0 {
                            ScreenTimeManager.shared.updateCategorySocial(v)
                            // Propager immédiatement aux groupes
                            ScreenTimeManager.shared.updateLocalGroups(appState: AppState.shared)
                        }

                    case "history":
                        // Format: pakt2://history?d=2026-03-12:300,2026-03-13:250,...
                        guard let param = components.queryItems?.first(where: { $0.name == "d" })?.value else { return }
                        // Cache local pour le graphe du profil (pas besoin d'auth)
                        ScreenTimeManager.shared.updateProfileHistory(param)

                        for entry in param.split(separator: ",") {
                            let parts = entry.split(separator: ":")
                            guard parts.count == 2, let minutes = Int(parts[1]), minutes > 0, minutes <= 1440 else { continue }
                            let dateStr = String(parts[0])
                            Task { try? await APIClient.shared.syncScore(minutes: minutes, date: dateStr) }
                        }

                    default: break
                    }
                }
        }
    }
}
