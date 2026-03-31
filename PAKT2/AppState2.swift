import SwiftUI
import Combine

class AppState: ObservableObject {
    static let shared = AppState()
    private var cancellables = Set<AnyCancellable>()

    @Published var profileUIImage: UIImage? = nil
    @Published var profileImage  : Image?   = nil
    @Published var goalHours     : Double   = 3.0
    @Published var socialGoalHours: Double   = 1.0
    @Published var userName      : String   = ""
    @Published var isOnboarded   : Bool     = false
    @Published var groups        : [Group]  = []

    // UID du compte connecté — source de vérité pour "isMe"
    // Utilise Firebase Auth si disponible, sinon le lastUID sauvegardé localement
    var currentUID: String {
        AuthManager.shared.currentUser?.id
        ?? UserDefaults.standard.string(forKey: UDKey.lastUID)
        ?? ""
    }

    // isMe : ce membre appartient-il au compte connecté ?
    func isMe(_ member: Member) -> Bool {
        !currentUID.isEmpty && member.uid == currentUID
    }

    // MARK: - Clés UserDefaults toutes préfixées par uid

    private func key(_ base: String, uid: String? = nil) -> String {
        let id = uid ?? currentUID
        return id.isEmpty ? base : "\(base)_\(id)"
    }

    // MARK: - Init

    init() {}

    // MARK: - Chargement du compte (appelé après connexion)

    func loadAccount(uid: String, firstName: String, goalHours: Double) {
        self.userName   = firstName
        self.goalHours  = goalHours
        self.isOnboarded = true

        // Sauvegarder les préférences sous cet uid
        UserDefaults.standard.set(firstName,  forKey: key("userName",   uid: uid))
        UserDefaults.standard.set(goalHours,  forKey: key("goalHours",  uid: uid))
        UserDefaults.standard.set(true,       forKey: key("isOnboarded", uid: uid))
        UserDefaults.standard.set(uid,        forKey: UDKey.lastUID)
        UserDefaults.standard.synchronize()

        // Partager uid/name/goals avec l'extension (App Group + Keychain)
        let ud = UserDefaults(suiteName: kAppGroupID)
        ud?.set(uid, forKey: "currentUID")
        ud?.set(firstName, forKey: "currentUserName")
        ud?.set(Int(goalHours * 60), forKey: "goalMinutes")
        ud?.set(Int(socialGoalHours * 60), forKey: "socialGoalMinutes")
        ud?.synchronize()
        AuthManager.shared.keychainWrite(key: "pakt_uid", value: uid)
        AuthManager.shared.keychainWrite(key: "pakt_username", value: firstName)
        AuthManager.shared.keychainWrite(key: "pakt_socialGoal", value: "\(Int(socialGoalHours * 60))")

        reloadProfilePhoto(uid: uid)
        if profileUIImage == nil {
            Task {
                if let img = await AuthManager.shared.fetchProfilePhoto(uid: uid) {
                    await MainActor.run {
                        profileUIImage = img
                        profileImage   = Image(uiImage: img)
                        if let data = img.jpegData(compressionQuality: 0.7) {
                            try? data.write(to: photoURL(uid: uid))
                        }
                    }
                }
            }
        }
        loadGroups(uid: uid)
        setupWebSocketSubscriptions()

        // Charger les stats screen time et sync
        ScreenTimeManager.shared.loadProfileCache()
        ScreenTimeManager.shared.updateLocalGroups(appState: self)
        Task { await self.syncFromBackend() }
    }

    // MARK: - Restauration au lancement (avant connexion backend)

    func restoreLastSession() {
        guard let uid = UserDefaults.standard.string(forKey: UDKey.lastUID), !uid.isEmpty else {
            return
        }
        let savedGoal = UserDefaults.standard.double(forKey: key("goalHours", uid: uid))
        goalHours  = savedGoal > 0 ? savedGoal : 3.0
        let savedSocialGoal = UserDefaults.standard.double(forKey: key("socialGoalHours", uid: uid))
        socialGoalHours = savedSocialGoal > 0 ? savedSocialGoal : 1.0
        userName   = UserDefaults.standard.string(forKey: key("userName",   uid: uid)) ?? ""
        isOnboarded = UserDefaults.standard.bool(forKey: key("isOnboarded", uid: uid))

        // Partager uid/name avec l'extension (App Group + Keychain) — APRÈS avoir chargé userName
        let ud = UserDefaults(suiteName: kAppGroupID)
        ud?.set(uid, forKey: "currentUID")
        ud?.set(userName, forKey: "currentUserName")
        ud?.synchronize()
        AuthManager.shared.keychainWrite(key: "pakt_uid", value: uid)
        AuthManager.shared.keychainWrite(key: "pakt_username", value: userName)
        AuthManager.shared.keychainWrite(key: "pakt_socialGoal", value: "\(Int(socialGoalHours * 60))")
        reloadProfilePhoto(uid: uid)
        if profileUIImage == nil {
            Task {
                if let img = await AuthManager.shared.fetchProfilePhoto(uid: uid) {
                    await MainActor.run {
                        profileUIImage = img
                        profileImage   = Image(uiImage: img)
                        if let data = img.jpegData(compressionQuality: 0.7) {
                            try? data.write(to: photoURL(uid: uid))
                        }
                    }
                }
            }
        }
        loadGroups(uid: uid)
    }

    // MARK: - Photo (FileManager, not UserDefaults — avoids 4MB UD overflow)

    private func photoURL(uid: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(uid).jpg")
    }

    func reloadProfilePhoto(uid: String? = nil) {
        let id = uid ?? currentUID
        guard !id.isEmpty else {
            profileUIImage = nil
            profileImage   = nil
            return
        }
        // Migrate from UD if file doesn't exist yet
        let url = photoURL(uid: id)
        if !FileManager.default.fileExists(atPath: url.path),
           let data = UserDefaults.standard.data(forKey: key("profilePhoto", uid: id)) {
            try? data.write(to: url)
            UserDefaults.standard.removeObject(forKey: key("profilePhoto", uid: id))
            UserDefaults.standard.removeObject(forKey: "profilePhotoCache_\(id)")
        }
        guard let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data) else {
            profileUIImage = nil
            profileImage   = nil
            return
        }
        profileUIImage = uiImage
        profileImage   = Image(uiImage: uiImage)
    }

    func saveImage(_ uiImage: UIImage) {
        guard !currentUID.isEmpty else { return }
        if let data = uiImage.jpegData(compressionQuality: 0.7) {
            try? data.write(to: photoURL(uid: currentUID))
            // Remove old UD entries to free space
            UserDefaults.standard.removeObject(forKey: key("profilePhoto"))
            UserDefaults.standard.removeObject(forKey: "profilePhotoCache_\(currentUID)")
        }
        objectWillChange.send()
        profileUIImage = uiImage
        profileImage   = Image(uiImage: uiImage)
        Task { try? await AuthManager.shared.uploadProfilePhoto(uiImage) }
    }

    // MARK: - Goal

    func updateGoalHours(_ hours: Double) {
        goalHours = hours
        UserDefaults(suiteName: kAppGroupID)?.set(Int(hours * 60), forKey: "goalMinutes")
        UserDefaults(suiteName: kAppGroupID)?.synchronize()
        guard !currentUID.isEmpty else { return }
        UserDefaults.standard.set(hours, forKey: key("goalHours"))
        UserDefaults.standard.synchronize()
        Task { await AuthManager.shared.updateGoal(hours: hours) }
    }

    func updateSocialGoalHours(_ hours: Double) {
        socialGoalHours = hours
        guard !currentUID.isEmpty else { return }
        UserDefaults.standard.set(hours, forKey: key("socialGoalHours"))
        let mins = Int(hours * 60)
        UserDefaults(suiteName: kAppGroupID)?.set(mins, forKey: "socialGoalMinutes")
        AuthManager.shared.keychainWrite(key: "pakt_socialGoal", value: "\(mins)")
        UserDefaults.standard.synchronize()
    }

    // Group photos removed — feature not used

    // MARK: - WebSocket Subscriptions

    func setupWebSocketSubscriptions() {
        cancellables.removeAll()

        // Score updates from other users (+ propre score via broadcast)
        WebSocketManager.shared.onScoreUpdated
            .collect(.byTime(DispatchQueue.main, .seconds(2)))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updates in
                guard let self, !updates.isEmpty else { return }
                let myUid = self.currentUID
                for update in updates {
                    // Ignorer les updates de mon propre score — le local (DAR/Monitor) fait autorité
                    guard update.userId != myUid else { continue }

                    for gi in self.groups.indices {
                        for mi in self.groups[gi].members.indices {
                            if self.groups[gi].members[mi].uid == update.userId {
                                let oldToday = self.groups[gi].members[mi].todayMinutes
                                let oldTodaySocial = self.groups[gi].members[mi].todaySocialMinutes

                                self.groups[gi].members[mi].todayMinutes = update.minutes
                                self.groups[gi].members[mi].todaySocialMinutes = update.socialMinutes

                                // Adjust monthMinutes so the "Total" ranking stays consistent
                                let delta = max(0, update.minutes - oldToday)
                                if self.groups[gi].members[mi].monthMinutes > 0 {
                                    self.groups[gi].members[mi].monthMinutes += delta
                                } else if update.minutes > 0 {
                                    self.groups[gi].members[mi].monthMinutes = update.minutes
                                }
                                let deltaSocial = max(0, update.socialMinutes - oldTodaySocial)
                                if self.groups[gi].members[mi].monthSocialMinutes > 0 {
                                    self.groups[gi].members[mi].monthSocialMinutes += deltaSocial
                                } else if update.socialMinutes > 0 {
                                    self.groups[gi].members[mi].monthSocialMinutes = update.socialMinutes
                                }
                            }
                        }
                    }
                }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Group membership changes — sync ciblé, pas full sync
        WebSocketManager.shared.onGroupUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                if update.type == "group_deleted" {
                    self.groups.removeAll { $0.id.uuidString == update.groupId }
                    self.saveGroupsLocal()
                } else {
                    // Recharger juste les groupes (pas le profil, pas les scores)
                    Task { await self.refreshGroupsOnly() }
                }
            }
            .store(in: &cancellables)

        // Pending scores from extension
        WebSocketManager.shared.onPendingScore
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                guard let self else { return }
                if pending.minutes > 0 {
                    ScreenTimeManager.shared.profileToday = pending.minutes
                }
                if pending.socialMinutes > 0 {
                    ScreenTimeManager.shared.categorySocial = pending.socialMinutes
                }
                ScreenTimeManager.shared.updateLocalGroups(appState: self)
            }
            .store(in: &cancellables)
    }

    // MARK: - Groups local storage (par uid)

    private func loadGroups(uid: String) {
        guard let data = UserDefaults.standard.data(forKey: key("groupsData", uid: uid)) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let decoded = try? decoder.decode([GroupData].self, from: data) {
            groups = decoded.map { $0.toGroup() }.filter { !$0.isDemo }
        }
    }

    func saveGroupsLocal() {
        guard !currentUID.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(groups.map { GroupData(from: $0) }) {
            UserDefaults.standard.set(data, forKey: key("groupsData"))
            UserDefaults.standard.synchronize()
        }
    }

    // MARK: - Sync Backend

    func syncFromBackend() async {
        guard let user = AuthManager.shared.currentUser else {
            print("[PAKT Sync] SKIPPED — currentUser is nil. isLoggedIn=\(AuthManager.shared.isLoggedIn) token=\(AuthManager.shared.accessToken != nil)")
            return
        }
        print("[PAKT Sync] Starting for user: \(user.id)")

        await MainActor.run {
            userName  = user.firstName
            goalHours = user.goalHours
            // S'assurer que lastUID est à jour avec le compte Auth actuel
            if UserDefaults.standard.string(forKey: UDKey.lastUID) != user.id {
                UserDefaults.standard.set(user.id, forKey: UDKey.lastUID)
            }
            reloadProfilePhoto(uid: user.id)
        }

        let apiGroups: [APIClient.APIGroup]?
        do {
            apiGroups = try await APIClient.shared.listGroups()
            print("[PAKT Sync] API returned \(apiGroups?.count ?? 0) groups")
        } catch {
            apiGroups = nil
            print("[PAKT Sync] listGroups FAILED: \(error)")
        }
        // Ne pas écraser les groupes locaux si l'API échoue ou retourne vide
        guard let apiGroups, !apiGroups.isEmpty else {
            // Quand même propager les données screen time
            await MainActor.run {
                ScreenTimeManager.shared.loadProfileCache()
                ScreenTimeManager.shared.updateLocalGroups(appState: self)
            }
            let uid = currentUID
            if !uid.isEmpty { ScreenTimeManager.shared.fetchSinceStartCumulative(uid: uid, appState: self) }
            return
        }
        let remoteGroups = apiGroups.map { $0.toGroup() }
        await MainActor.run {
            mergeRemoteGroups(remoteGroups)
            // Propager les données screen time locales aux groupes fraîchement chargés
            ScreenTimeManager.shared.loadProfileCache()
            ScreenTimeManager.shared.updateLocalGroups(appState: self)
        }
        // Charger le cumul historique depuis le backend (userScores)
        let uid = currentUID
        if !uid.isEmpty {
            ScreenTimeManager.shared.fetchSinceStartCumulative(uid: uid, appState: self)
        }
    }

    func syncFromFirebase() async { await syncFromBackend() }

    /// Sync léger : recharge juste les groupes sans refaire profil/scores
    func refreshGroupsOnly() async {
        guard let apiGroups = try? await APIClient.shared.listGroups(), !apiGroups.isEmpty else { return }
        let remoteGroups = apiGroups.map { $0.toGroup() }
        await MainActor.run {
            mergeRemoteGroups(remoteGroups)
            ScreenTimeManager.shared.loadProfileCache()
            ScreenTimeManager.shared.updateLocalGroups(appState: self)
        }
    }

    private func mergeRemoteGroups(_ remote: [Group]) {
        // Si le backend retourne vide, vider les groupes locaux
        guard !remote.isEmpty else {
            groups = []
            saveGroupsLocal()
            return
        }

        // Le backend est la source de vérité pour la structure des groupes
        // Mais préserver scope/trackedApps local tant que le backend ne les supporte pas
        var merged = remote
        for i in merged.indices {
            if let local = groups.first(where: { $0.id == merged[i].id }) {
                if local.scope == .apps || local.scope == .social {
                    merged[i].scope = local.scope
                    merged[i].trackedApps = local.trackedApps
                }
            }
        }
        groups = merged
        saveGroupsLocal()
    }

    // MARK: - Groups CRUD

    func addGroup(_ group: Group) {
        Task {
            do {
                let apiGroup = try await APIClient.shared.createGroup(
                    name: group.name, mode: group.mode.rawValue, scope: group.scope.rawValue,
                    goalMinutes: group.goalMinutes, duration: group.duration.rawValue, photoName: group.photoName,
                    stake: group.stake, requiredPlayers: group.requiredPlayers,
                    trackedApps: group.trackedApps
                )
                var serverGroup = apiGroup.toGroup()
                // Le backend ne supporte pas encore scope "apps" / trackedApps
                // Préserver les valeurs locales
                serverGroup.scope = group.scope
                serverGroup.trackedApps = group.trackedApps
                await MainActor.run {
                    self.groups.append(serverGroup)
                    self.saveGroupsLocal()
                }
                PaktAnalytics.createGroup(mode: group.mode.rawValue, scope: group.scope.rawValue, duration: group.duration.rawValue)
            } catch {
                // Fallback : ajouter localement si le réseau échoue
                await MainActor.run {
                    var g = group
                    g.creatorId = self.currentUID
                    self.groups.append(g)
                    self.saveGroupsLocal()
                }
            }
        }
    }

    func joinGroup(code: String) async -> JoinResult {
        let uid = AuthManager.shared.currentUser?.id ?? currentUID
        guard !uid.isEmpty else { return .error("not logged in") }

        guard let apiGroup = try? await APIClient.shared.getGroupByCode(code) else { return .error("group not found") }
        let remote = apiGroup.toGroup()
        if groups.contains(where: { $0.id == remote.id }) {
            return .alreadyMember
        }

        let minutes = ScreenTimeManager.shared.readTodayMinutes()
        let newMember = Member(
            uid:          uid,
            name:         userName,
            todayMinutes: minutes,
            weekMinutes:  0,
            monthMinutes: 0,
            history:      []
        )

        var updatedGroup = remote
        updatedGroup.members.append(newMember)

        await MainActor.run {
            groups.append(updatedGroup)
            saveGroupsLocal()
        }

        do {
            _ = try await APIClient.shared.joinGroup(remote.id.uuidString)
        } catch {
            // Rollback local si le backend échoue
            await MainActor.run { groups.removeAll { $0.id == remote.id }; saveGroupsLocal() }
            return .error("network error")
        }

        PaktAnalytics.joinGroup()
        return .success(updatedGroup)
    }


    func leaveGroup(_ group: Group) {
        PaktAnalytics.leaveGroup()
        let uid = currentUID
        // Retirer localement
        groups.removeAll { $0.id == group.id }
        saveGroupsLocal()
        // Retirer du backend
        Task {
            try? await APIClient.shared.leaveGroup(group.id.uuidString)
        }
    }

    func updateUsername(_ newName: String) async -> Bool {
        let uid     = currentUID
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !uid.isEmpty, trimmed.count >= 2 else { return false }

        // Le backend gère la vérification d'unicité ET la mise à jour atomiquement
        do {
            try await AuthManager.shared.updateUsername(trimmed)
        } catch {
            print("updateUsername error: \(error.localizedDescription)")
            return false
        }

        // Mettre à jour localement après succès backend
        await MainActor.run {
            userName = trimmed
            UserDefaults.standard.set(trimmed, forKey: "userName_\(uid)")
            UserDefaults.standard.synchronize()
            for gi in groups.indices {
                for mi in groups[gi].members.indices where groups[gi].members[mi].uid == uid {
                    groups[gi].members[mi].name = trimmed
                }
            }
            saveGroupsLocal()
        }
        return true
    }

    func updateGroup(_ group: Group) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
            saveGroupsLocal()
        }
    }

    func deleteGroup(_ group: Group) {
        groups.removeAll { $0.id == group.id }
        saveGroupsLocal()
        Task {
            try? await APIClient.shared.deleteGroup(group.id.uuidString)
        }
    }

    // MARK: - Sign out

    func signOut() {
        PaktAnalytics.signOut()
        // Stopper tous les listeners avant de vider les données
        FriendManager.shared.stopListening()
        InvitationManager.shared.stopListening()
        cancellables.removeAll()

        // Nettoyer les données user-specific AVANT de perdre le uid
        let uid = currentUID
        if !uid.isEmpty {
            for k in ["userName", "goalHours", "socialGoalHours", "isOnboarded", "groupsData", "profilePhoto"] {
                UserDefaults.standard.removeObject(forKey: "\(k)_\(uid)")
            }
            UserDefaults.standard.removeObject(forKey: "profilePhotoCache_\(uid)")
        }

        AuthManager.shared.signOut()
        WebSocketManager.shared.disconnect()
        UserDefaults.standard.removeObject(forKey: UDKey.lastUID)
        isOnboarded    = false
        userName       = ""
        goalHours      = 3.0
        profileUIImage = nil
        profileImage   = nil
        groups         = []
    }
}

// MARK: - Codable

struct GroupData: Codable {
    let id: String; let name: String; let code: String
    let mode: String; let scope: String; let goalMinutes: Int; let duration: String
    let startDate: Date; let isFinished: Bool; let creatorId: String
    let photoName: String; let isDemo: Bool
    let stake: String; let requiredPlayers: Int; let status: String
    let trackedApps: [String]
    let members: [MemberData]

    init(from g: Group) {
        id = g.id.uuidString; name = g.name; code = g.code
        mode = g.mode.rawValue; scope = g.scope.rawValue
        goalMinutes = g.goalMinutes
        duration = g.duration.rawValue; startDate = g.startDate
        isFinished = g.isFinished; creatorId = g.creatorId
        photoName = g.photoName; isDemo = g.isDemo
        stake = g.stake; requiredPlayers = g.requiredPlayers; status = g.status.rawValue
        trackedApps = g.trackedApps
        members = g.members.map { MemberData(from: $0) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        code = try c.decode(String.self, forKey: .code)
        mode = try c.decode(String.self, forKey: .mode)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "total"
        goalMinutes = try c.decode(Int.self, forKey: .goalMinutes)
        duration = try c.decode(String.self, forKey: .duration)
        startDate = try c.decode(Date.self, forKey: .startDate)
        isFinished = try c.decode(Bool.self, forKey: .isFinished)
        creatorId = try c.decode(String.self, forKey: .creatorId)
        photoName = try c.decode(String.self, forKey: .photoName)
        isDemo = try c.decode(Bool.self, forKey: .isDemo)
        stake = try c.decodeIfPresent(String.self, forKey: .stake) ?? "For fun"
        requiredPlayers = try c.decodeIfPresent(Int.self, forKey: .requiredPlayers) ?? 2
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        trackedApps = try c.decodeIfPresent([String].self, forKey: .trackedApps) ?? []
        members = try c.decode([MemberData].self, forKey: .members)
    }

    func toGroup() -> Group {
        Group(
            id: UUID(uuidString: id) ?? UUID(), name: name, code: code,
            mode: GameMode(rawValue: mode) ?? .competitive,
            scope: ChallengeScope(rawValue: scope) ?? .total,
            goalMinutes: goalMinutes,
            duration: ChallengeDuration(rawValue: duration) ?? .oneMonth,
            startDate: startDate, members: members.map { $0.toMember() },
            isFinished: isFinished, creatorId: creatorId,
            photoName: photoName, isDemo: isDemo,
            stake: stake, requiredPlayers: requiredPlayers,
            status: PaktStatus(rawValue: status) ?? .active,
            trackedApps: trackedApps
        )
    }
}

struct MemberData: Codable {
    let uid: String; let name: String
    let todayMinutes: Int; let weekMinutes: Int; let monthMinutes: Int
    let todaySocialMinutes: Int; let monthSocialMinutes: Int
    let bio: String; let history: [DataPointData]

    init(from m: Member) {
        uid = m.uid; name = m.name
        todayMinutes = m.todayMinutes; weekMinutes = m.weekMinutes
        monthMinutes = m.monthMinutes
        todaySocialMinutes = m.todaySocialMinutes
        monthSocialMinutes = m.monthSocialMinutes
        bio = m.bio
        history = m.history.map { DataPointData(from: $0) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        name = try c.decode(String.self, forKey: .name)
        todayMinutes = try c.decode(Int.self, forKey: .todayMinutes)
        weekMinutes = try c.decode(Int.self, forKey: .weekMinutes)
        monthMinutes = try c.decode(Int.self, forKey: .monthMinutes)
        todaySocialMinutes = try c.decodeIfPresent(Int.self, forKey: .todaySocialMinutes) ?? 0
        monthSocialMinutes = try c.decodeIfPresent(Int.self, forKey: .monthSocialMinutes) ?? 0
        bio = try c.decode(String.self, forKey: .bio)
        history = try c.decode([DataPointData].self, forKey: .history)
    }

    func toMember() -> Member {
        Member(uid: uid, name: name, todayMinutes: todayMinutes,
               weekMinutes: weekMinutes, monthMinutes: monthMinutes,
               todaySocialMinutes: todaySocialMinutes,
               monthSocialMinutes: monthSocialMinutes,
               history: history.map { $0.toDataPoint() }, bio: bio)
    }
}

struct DataPointData: Codable {
    let day: String; let minutes: Int
    init(from dp: DataPoint) { day = dp.day; minutes = dp.minutes }
    func toDataPoint() -> DataPoint { DataPoint(day: day, minutes: minutes) }
}

// MARK: - APIGroup → Group conversion

extension APIClient.APIGroup {
    func toGroup() -> Group {
        Group(
            id: UUID(uuidString: id) ?? UUID(),
            name: name, code: code,
            mode: GameMode(rawValue: mode) ?? .competitive,
            scope: ChallengeScope(rawValue: scope) ?? .total,
            goalMinutes: goalMinutes,
            duration: ChallengeDuration(rawValue: duration) ?? .oneMonth,
            startDate: startDate,
            members: members.map { m in
                Member(uid: m.userId, name: m.username, todayMinutes: 0, weekMinutes: 0, monthMinutes: 0, history: [], bio: m.bio)
            },
            isFinished: isFinished,
            creatorId: creatorId,
            photoName: photoName,
            isDemo: isDemo,
            stake: stake, requiredPlayers: requiredPlayers,
            status: PaktStatus(rawValue: status) ?? .active,
            trackedApps: trackedApps ?? []
        )
    }
}
