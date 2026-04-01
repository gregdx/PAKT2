import SwiftUI
import Foundation
import Combine

// MARK: - AppUser

struct AppUser: Identifiable, Codable, Equatable {
    var id             : String
    var firstName      : String
    var email          : String
    var goalHours      : Double
    var bio            : String
    var memberSince    : Date
    var medals         : [Medal]
    var emailVerified  : Bool = false
    init(id: String, firstName: String, email: String, goalHours: Double = 3.0) {
        self.id          = id
        self.firstName   = firstName
        self.email       = email
        self.goalHours   = goalHours
        self.bio         = ""
        self.memberSince = Date()
        self.medals      = []
    }
}

// MARK: - Medal

struct Medal: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var groupName: String
    var date: Date
    var mode: String        // "Competitive" ou "Collective"
    var avgMinutes: Int     // moyenne du gagnant
    var goalMinutes: Int
}

// MARK: - Enums

enum GameMode: String, Codable, CaseIterable {
    case competitive = "Competitive"
    case collective  = "Collective"

    var displayName: String {
        switch self {
        case .competitive: return L10n.t("competitive")
        case .collective:  return L10n.t("collective")
        }
    }
}

enum ChallengeDuration: String, Codable, CaseIterable {
    case oneDay    = "1 day"
    case oneWeek   = "1 week"
    case twoWeeks  = "2 weeks"
    case oneMonth  = "1 month"

    var days: Int {
        switch self {
        case .oneDay:    return 1
        case .oneWeek:   return 7
        case .twoWeeks:  return 14
        case .oneMonth:  return 30
        }
    }

    var displayName: String {
        switch self {
        case .oneDay:    return L10n.t("1_day")
        case .oneWeek:   return L10n.t("1_week")
        case .twoWeeks:  return L10n.t("2_weeks")
        case .oneMonth:  return L10n.t("1_month")
        }
    }
}

enum ChallengeScope: String, Codable, CaseIterable {
    case total  = "total"
    case social = "social"
    case apps   = "apps"    // Track specific apps (Instagram, TikTok, etc.)
}

enum Period: String, CaseIterable {
    case total = "total"
    case day   = "day"

    var displayName: String {
        switch self {
        case .total: return L10n.t("period_final")
        case .day:   return L10n.t("period_day")
        }
    }
}

enum PaktStatus: String, Codable, CaseIterable {
    case pending  = "pending"
    case active   = "active"
    case finished = "finished"
}

enum StakeOption: String, CaseIterable {
    case forFun        = "For fun"
    case lastPaysRound = "Last pays a round"
    case fiveEuro      = "5\u{20AC}"
    case tenEuro       = "10\u{20AC}"
    case twentyEuro    = "20\u{20AC}"
    case dinner        = "Dinner"
    case custom        = "Custom"

    var displayName: String {
        switch self {
        case .forFun:        return L10n.t("stake_for_fun")
        case .lastPaysRound: return L10n.t("stake_last_pays")
        case .fiveEuro:      return "5\u{20AC}"
        case .tenEuro:       return "10\u{20AC}"
        case .twentyEuro:    return "20\u{20AC}"
        case .dinner:        return L10n.t("stake_dinner")
        case .custom:        return L10n.t("stake_custom")
        }
    }
}

// MARK: - Achievements

struct AchievementDef: Identifiable {
    let id: String
    let icon: String    // SF Symbol name
    let nameEN: String
    let nameFR: String
    let color: Color

    var name: String {
        nameEN
    }

    static let all: [AchievementDef] = [
        AchievementDef(id: "joined_group",     icon: "person.2",              nameEN: "Joined a group",      nameFR: "A rejoint un groupe",     color: Color(red: 0.35, green: 0.48, blue: 0.95)),
        AchievementDef(id: "created_group",    icon: "crown",                 nameEN: "Created a group",     nameFR: "A créé un groupe",        color: Color(red: 1.00, green: 0.75, blue: 0.00)),
        AchievementDef(id: "invited_friend",   icon: "paperplane.fill",       nameEN: "Invited a friend",    nameFR: "A invité un ami",         color: Color(red: 0.20, green: 0.78, blue: 0.60)),
        AchievementDef(id: "first_under_3h",   icon: "clock.badge.checkmark", nameEN: "First day under 3h",  nameFR: "Premier jour sous 3h",    color: Color(red: 0.00, green: 0.75, blue: 0.36)),
        AchievementDef(id: "streak_3",         icon: "flame",                 nameEN: "3-day streak",        nameFR: "Streak de 3 jours",       color: Color(red: 1.00, green: 0.50, blue: 0.00)),
        AchievementDef(id: "streak_7",         icon: "flame.fill",            nameEN: "7-day streak",        nameFR: "Streak de 7 jours",       color: Color(red: 1.00, green: 0.35, blue: 0.10)),
        AchievementDef(id: "streak_30",        icon: "bolt.fill",             nameEN: "30-day streak",       nameFR: "Streak de 30 jours",      color: Color(red: 0.93, green: 0.18, blue: 0.09)),
        AchievementDef(id: "won_challenge",    icon: "trophy.fill",           nameEN: "Won a challenge",     nameFR: "A gagné un défi",         color: Color(red: 1.00, green: 0.84, blue: 0.00)),
        AchievementDef(id: "week_under_goal",  icon: "star.fill",             nameEN: "7 days under goal",   nameFR: "7 jours sous l'objectif", color: Color(red: 0.52, green: 0.18, blue: 0.72)),
        AchievementDef(id: "month_under_goal", icon: "target",                nameEN: "30 days under goal",  nameFR: "30 jours sous l'objectif",color: Color(red: 0.85, green: 0.20, blue: 0.50)),
        AchievementDef(id: "five_friends",     icon: "person.3.fill",         nameEN: "Made 5 friends",      nameFR: "5 amis",                  color: Color(red: 0.30, green: 0.65, blue: 0.90)),
        AchievementDef(id: "signed_pakt",      icon: "signature",             nameEN: "Signed a pakt",       nameFR: "A signé un pacte",        color: Color(red: 0.40, green: 0.40, blue: 0.40)),
        AchievementDef(id: "veteran",          icon: "calendar.badge.clock",  nameEN: "Member for 1 month",  nameFR: "Membre depuis 1 mois",    color: Color(red: 0.60, green: 0.45, blue: 0.30)),
    ]
}

struct UserProfile: Decodable {
    let id: String
    let username: String
    let bio: String
    let memberSince: Date
    let achievements: [String]
}

// MARK: - DataPoint

struct DataPoint: Identifiable {
    let id     = UUID()
    let day    : String
    let minutes: Int
}

// MARK: - Member
// uid = identifiant unique du user. Vide pour les membres démo/fictifs.
// isMe est calculé à l'affichage : member.uid == currentUser.uid

struct Member: Identifiable {
    let id           = UUID()
    var uid          : String = ""   // Firebase uid — vide pour membres fictifs
    var name         : String
    var todayMinutes : Int
    var weekMinutes  : Int
    var monthMinutes : Int
    var todaySocialMinutes : Int = 0
    var monthSocialMinutes : Int = 0
    var history      : [DataPoint]
    var bio          : String = ""

    // Moyenne depuis l'historique réel
    var weekAvgMinutes: Int {
        let recent = history.suffix(7).map { $0.minutes }.filter { $0 > 0 }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0, +) / recent.count
    }
    var monthAvgMinutes: Int {
        let all = history.map { $0.minutes }.filter { $0 > 0 }
        guard !all.isEmpty else { return 0 }
        return all.reduce(0, +) / all.count
    }

    func goalReached(limit: Int) -> Bool { todayMinutes <= limit }
    var initial: String { String(name.prefix(1)).uppercased() }
}

// MARK: - Group

struct Group: Identifiable, Hashable {
    static func == (lhs: Group, rhs: Group) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id          : UUID = UUID()
    var name        : String
    var code        : String
    var mode        : GameMode
    var scope       : ChallengeScope = .total
    var goalMinutes : Int
    var duration    : ChallengeDuration
    var startDate   : Date
    var members     : [Member]
    var isFinished  : Bool   = false
    var creatorId   : String = ""
    var photoName   : String = ""
    var isDemo      : Bool   = false
    var stake          : String     = "For fun"
    var requiredPlayers: Int        = 2
    var status         : PaktStatus = .active
    var trackedApps    : [String]   = []  // App keywords to track (e.g. ["instagram", "tiktok"])

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: duration.days, to: startDate) ?? startDate
    }
    var daysLeft: Int {
        guard status != .pending else { return duration.days }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }
    var challengeProgress: Double {
        min(Double(duration.days - daysLeft) / Double(duration.days), 1.0)
    }
    /// Minutes clé pour le classement (dépend du scope)
    func rankMinutes(_ m: Member) -> Int {
        scope == .social ? m.monthSocialMinutes : m.monthMinutes
    }
    func todayRankMinutes(_ m: Member) -> Int {
        scope == .social ? m.todaySocialMinutes : m.todayMinutes
    }
    var rankedMembers: [Member] {
        members.sorted {
            let a = rankMinutes($0), b = rankMinutes($1)
            return a == b ? $0.name < $1.name : a < b
        }
    }
    var averageMinutes: Int {
        guard !members.isEmpty else { return 0 }
        return members.map { $0.todayMinutes }.reduce(0, +) / members.count
    }
    var collectiveGoalReached: Bool { averageMinutes <= goalMinutes }
    var signaturesNeeded: Int { max(0, requiredPlayers - members.count) }
    var isPending: Bool { status == .pending }
    var isActive: Bool { status == .active }
    var successRate: Int {
        guard !members.isEmpty else { return 0 }
        return (members.filter { $0.goalReached(limit: goalMinutes) }.count * 100) / members.count
    }
}

// MARK: - App Definitions (for per-app tracking)

struct AppDef: Identifiable {
    let id: String        // keyword used for matching (e.g. "instagram")
    let name: String      // display name
    let letter: String    // fallback letter shown in icon
    let color: Color      // brand color (fallback background)
    let bundleId: String  // iOS bundle ID for iTunes icon lookup

    static let all: [AppDef] = [
        AppDef(id: "instagram",  name: "Instagram",  letter: "I",  color: Color(red: 0.88, green: 0.19, blue: 0.42), bundleId: "com.burbn.instagram"),
        AppDef(id: "tiktok",     name: "TikTok",     letter: "T",  color: Color(red: 0.0,  green: 0.0,  blue: 0.0),  bundleId: "com.zhiliaoapp.musically"),
        AppDef(id: "snapchat",   name: "Snapchat",   letter: "S",  color: Color(red: 1.0,  green: 0.98, blue: 0.0),  bundleId: "com.toyopagroup.picaboo"),
        AppDef(id: "twitter",    name: "X",           letter: "X",  color: Color(red: 0.0,  green: 0.0,  blue: 0.0),  bundleId: "com.atebits.Tweetie2"),
        AppDef(id: "facebook",   name: "Facebook",    letter: "f",  color: Color(red: 0.23, green: 0.35, blue: 0.60), bundleId: "com.facebook.Facebook"),
        AppDef(id: "messenger",  name: "Messenger",   letter: "M",  color: Color(red: 0.0,  green: 0.47, blue: 1.0),  bundleId: "com.facebook.Messenger"),
        AppDef(id: "whatsapp",   name: "WhatsApp",    letter: "W",  color: Color(red: 0.15, green: 0.68, blue: 0.38), bundleId: "net.whatsapp.WhatsApp"),
        AppDef(id: "telegram",   name: "Telegram",    letter: "T",  color: Color(red: 0.16, green: 0.57, blue: 0.87), bundleId: "ph.telegra.Telegraph"),
        AppDef(id: "discord",    name: "Discord",     letter: "D",  color: Color(red: 0.35, green: 0.40, blue: 0.95), bundleId: "com.hammerandchisel.discord"),
        AppDef(id: "reddit",     name: "Reddit",      letter: "R",  color: Color(red: 1.0,  green: 0.27, blue: 0.0),  bundleId: "com.reddit.Reddit"),
        AppDef(id: "threads",    name: "Threads",     letter: "@",  color: Color(red: 0.0,  green: 0.0,  blue: 0.0),  bundleId: "com.burbn.barcelona"),
        AppDef(id: "linkedin",   name: "LinkedIn",    letter: "in", color: Color(red: 0.0,  green: 0.47, blue: 0.71), bundleId: "com.linkedin.LinkedIn"),
        AppDef(id: "bereal",     name: "BeReal",      letter: "B",  color: Color(red: 0.0,  green: 0.0,  blue: 0.0),  bundleId: "AlexisBarrworeyat.BeReal-Photos-Amis"),
        AppDef(id: "pinterest",  name: "Pinterest",   letter: "P",  color: Color(red: 0.90, green: 0.12, blue: 0.17), bundleId: "pinterest"),
        AppDef(id: "youtube",    name: "YouTube",     letter: "Y",  color: Color(red: 1.0,  green: 0.0,  blue: 0.0),  bundleId: "com.google.ios.youtube"),
    ]

    static func find(_ id: String) -> AppDef? { all.first { $0.id == id } }
}

// MARK: - App Icon Cache (iTunes API)

final class AppIconCache: ObservableObject {
    static let shared = AppIconCache()
    @Published var icons: [String: UIImage] = [:]  // appId → icon
    private var loadingIds: Set<String> = []
    private let cacheDir: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("app_icons")

    init() {
        // Créer le dossier cache
        if let dir = cacheDir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        // Charger les icônes disque en mémoire
        for app in AppDef.all {
            if let img = loadFromDisk(app.id) { icons[app.id] = img }
        }
    }

    func preloadAll() {
        for app in AppDef.all where icons[app.id] == nil {
            fetchIcon(for: app)
        }
    }

    func fetchIcon(for app: AppDef) {
        guard icons[app.id] == nil, !loadingIds.contains(app.id) else { return }
        loadingIds.insert(app.id)

        let urlStr = "https://itunes.apple.com/lookup?bundleId=\(app.bundleId)&country=US"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let self else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let iconURL = first["artworkUrl512"] as? String ?? first["artworkUrl100"] as? String,
                  let imgURL = URL(string: iconURL) else {
                DispatchQueue.main.async { self.loadingIds.remove(app.id) }
                return
            }

            URLSession.shared.dataTask(with: imgURL) { imgData, _, _ in
                guard let imgData, let img = UIImage(data: imgData) else { return }
                self.saveToDisk(app.id, data: imgData)
                DispatchQueue.main.async {
                    self.icons[app.id] = img
                    self.loadingIds.remove(app.id)
                }
            }.resume()
        }.resume()
    }

    private func saveToDisk(_ id: String, data: Data) {
        guard let dir = cacheDir else { return }
        try? data.write(to: dir.appendingPathComponent("\(id).png"))
    }

    private func loadFromDisk(_ id: String) -> UIImage? {
        guard let dir = cacheDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent("\(id).png")) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - App Icon View (reusable)

struct AppIconView: View {
    let app: AppDef
    var size: CGFloat = 40
    @ObservedObject private var cache = AppIconCache.shared

    var body: some View {
        if let img = cache.icons[app.id] {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            // Fallback : lettre + couleur pendant le chargement
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(app.color)
                    .frame(width: size, height: size)
                Text(app.letter)
                    .font(.system(size: size * 0.45, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            .onAppear { cache.fetchIcon(for: app) }
        }
    }
}

// MARK: - Formatters

func formatTime(_ minutes: Int) -> String {
    "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
}
func formatAvg(_ minutes: Int) -> String { formatTime(minutes) + "/d" }


private let dateDisplayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "MMMM d, yyyy"
    return f
}()

func formatDate(_ date: Date) -> String {
    dateDisplayFormatter.string(from: date)
}

func generateGroupCode() -> String {
    let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "GRP-" + String((0..<4).compactMap { _ in chars.randomElement() })
}


func makeFakeHistory(_ base: Int) -> [DataPoint] {
    ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"].map {
        DataPoint(day: $0, minutes: max(10, base + Int.random(in: -40...40)))
    }
}

// MARK: - JoinResult

enum JoinResult {
    case success(Group)
    case alreadyMember
    case error(String)
}

// MARK: - Notifications

extension Notification.Name {
    static let goalDidChange = Notification.Name("goalDidChange")
}
