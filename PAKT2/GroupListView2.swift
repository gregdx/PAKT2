import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject var appState : AppState
    @ObservedObject private var invManager = InvitationManager.shared
    @Binding var selectedTab: Int
    @AppStorage("isDarkMode") private var isDarkMode = false
    @ObservedObject private var friendManager = FriendManager.shared
    @ObservedObject private var stManager = ScreenTimeManager.shared
    @State private var showCreate   = false
    @State private var showJoin     = false
    @State private var showNotifs   = false
    @State private var isRefreshing = false
    @State private var selectedFriendChat: AppUser? = nil
    @State private var searchText = ""
    @State private var homeFilter: HomeFilter = .groups

    enum HomeFilter: String, CaseIterable {
        case groups, friends
    }

    @State private var showFriends = false

    private var todayKey: String {
        ScreenTimeManager.dateFormatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        RefreshControl(isRefreshing: $isRefreshing) {
                            Task {
                                await appState.refreshGroupsOnly()
                                DispatchQueue.main.async { isRefreshing = false }
                            }
                        }
                        header
                        dailySummary
                        searchBar
                        homeFilterPills
                        if homeFilter == .groups {
                            if appState.groups.isEmpty {
                                emptyState
                            } else {
                                groupsOnlyList
                            }
                        } else {
                            friendsOnlyList
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $selectedGroupId) { gid in
                SwipeDismissView {
                    GroupDetailView(groupId: gid, isSheet: true)
                        .environmentObject(appState)
                } onDismiss: { selectedGroupId = nil }
            }
            .fullScreenCover(item: $selectedFriendChat) { friend in
                SwipeDismissView {
                    FriendDetailView(friend: friend)
                        .environmentObject(appState)
                } onDismiss: { selectedFriendChat = nil }
            }
            .sheet(isPresented: $showCreate, onDismiss: {
                // Track group creation when sheet is dismissed (group may have been created)
                if appState.groups.contains(where: { $0.creatorId == appState.currentUID }) {
                    PaktAnalytics.track(.groupCreated)
                }
            }) {
                CreateGroupView().environmentObject(appState)
            }
            .sheet(isPresented: $showJoin) {
                JoinGroupSheet(isPresented: $showJoin).environmentObject(appState)
            }
            .sheet(isPresented: $showNotifs) {
                NotificationsView().environmentObject(appState)
            }
            .sheet(isPresented: $showFriends) {
                FriendsView().environmentObject(appState)
            }
            .onAppear {
                appState.insertDemoGroupIfNeeded()
                Task { await appState.syncFromFirebase() }
                ScreenTimeManager.shared.syncToBackend(appState: appState)
                // Check for pending join code from deep link
                if let pending = UserDefaults.standard.string(forKey: "pendingJoinCode"), !pending.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingJoinCode")
                    showJoin = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("openJoinSheet"))) { notification in
                if let code = notification.object as? String, !code.isEmpty {
                    // Pre-fill and show join sheet
                    showJoin = true
                }
            }
        }
    }

    // MARK: - Daily Summary Hero Card

    private var dailySummary: some View {
        let today = stManager.profileToday
        let groups = appState.groups.filter { $0.status == .active && !$0.isCompleted }
        let leadingCount = groups.filter { g in
            let ranked = g.rankedMembers
            if let first = ranked.first, appState.isMe(first) { return true }
            return false
        }.count

        return VStack(spacing: 8) {
            Text(today > 0 ? formatTime(today) : "--")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(Theme.text)
                .contentTransition(.numericText())
            Text(L10n.t("today").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(1.5)
            if leadingCount > 0 {
                Text("#1 in \(leadingCount) \(leadingCount == 1 ? "group" : "groups")")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Header

    var header: some View {
        HStack(alignment: .center) {
            Text(L10n.t("home"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
            HStack(spacing: 8) {
                Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
                .accessibilityLabel("Create group")

                Button(action: { showJoin = true }) {
                    Image(systemName: "link")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
                .accessibilityLabel("Join group")

                Button(action: { showNotifs = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                        if !invManager.pending.isEmpty {
                            Circle()
                                .fill(Theme.red)
                                .frame(width: 10, height: 10)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Notifications")
            }
        }
        .padding(.horizontal, 24).padding(.top, 56).padding(.bottom, 28)
    }

    // MARK: - Search bar

    var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(Theme.textFaint)
            TextField(L10n.t("search_placeholder"), text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(Theme.text)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textFaint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.4))
        )
        .liquidGlass(cornerRadius: 12, style: .ultraThin)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Home filter pills

    var homeFilterPills: some View {
        HStack(spacing: 8) {
            ForEach(HomeFilter.allCases, id: \.self) { filter in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { homeFilter = filter }
                }) {
                    Text(filter == .groups ? L10n.t("groups") : L10n.t("friends_section"))
                        .font(.system(size: 15, weight: homeFilter == filter ? .semibold : .regular))
                        .foregroundColor(homeFilter == filter ? Theme.bg : Theme.textMuted)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background {
                            if homeFilter == filter {
                                RoundedRectangle(cornerRadius: 20).fill(Theme.text)
                            } else {
                                RoundedRectangle(cornerRadius: 20).fill(.clear).liquidGlass(cornerRadius: 20)
                            }
                        }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Empty state (first launch)

    var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)
                .padding(.top, 40)

            Text(L10n.t("welcome_empty_title"))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.text)

            VStack(spacing: 14) {
                Button(action: { showCreate = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                        Text(L10n.t("create_group"))
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.text.opacity(0.08)))
                    .liquidGlass(cornerRadius: 14, style: .ultraThin)
                }

                Button(action: { showJoin = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "link").font(.system(size: 16))
                        Text(L10n.t("join_group"))
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.text.opacity(0.08)))
                    .liquidGlass(cornerRadius: 14, style: .ultraThin)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Groups list

    @State private var selectedGroupId: UUID? = nil

    private func matchesSearch(_ text: String) -> Bool {
        searchText.isEmpty || text.localizedCaseInsensitiveContains(searchText)
    }

    var groupsOnlyList: some View {
        let uid = appState.currentUID
        let pendingGroups  = appState.groups.filter { $0.status == .pending && matchesSearch($0.name) }
        let activeGroups   = appState.groups.filter { $0.status == .active && !$0.isCompleted && matchesSearch($0.name) }
        let finishedGroups = appState.groups.filter { ($0.status == .finished || $0.isCompleted) && matchesSearch($0.name) }

        return VStack(spacing: 12) {
            if !pendingGroups.isEmpty {
                SectionTitle(text: L10n.t("pending_pakts"))
                ForEach(pendingGroups) { group in
                    let isCreator = !uid.isEmpty && group.creatorId == uid
                    Button(action: { selectedGroupId = group.id }) {
                        GroupCard(group: group, todayKey: todayKey)
                            .environmentObject(appState)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        if isCreator {
                            Button(role: .destructive) { appState.deleteGroup(group) } label: {
                                Label(L10n.t("delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !activeGroups.isEmpty {
                SectionTitle(text: L10n.t("active_pakts"))
                ForEach(activeGroups) { group in
                    let isCreator = !uid.isEmpty && group.creatorId == uid
                    Button(action: { selectedGroupId = group.id }) {
                        GroupCard(group: group, todayKey: todayKey)
                            .environmentObject(appState)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) { appState.leaveGroup(group) } label: {
                            Label(L10n.t("leave_group"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        if isCreator {
                            Button(role: .destructive) { appState.deleteGroup(group) } label: {
                                Label(L10n.t("delete_pakt"), systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !finishedGroups.isEmpty {
                SectionTitle(text: L10n.t("finished_pakts"))
                ForEach(finishedGroups) { group in
                    Button(action: { selectedGroupId = group.id }) {
                        GroupCard(group: group, todayKey: todayKey)
                            .environmentObject(appState)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) { appState.deleteGroup(group) } label: {
                            Label(L10n.t("delete_pakt"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    var friendsOnlyList: some View {
        let filtered = friendManager.friends.filter { matchesSearch($0.firstName) }
        return VStack(spacing: 12) {
            if filtered.isEmpty {
                VStack(spacing: 16) {
                    Text(L10n.t("no_friends"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textMuted)

                    Button(action: { showFriends = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus").font(.system(size: 15))
                            Text(L10n.t("add_friend"))
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .liquidGlass(cornerRadius: 16)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 40)
            } else {
                ForEach(filtered) { friend in
                    Button(action: { selectedFriendChat = friend }) {
                        FriendRow(friend: friend)
                            .environmentObject(appState)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 24)
    }

}

// MARK: - GroupCard

struct GroupCard: View {
    let group: Group
    let todayKey: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var chatManager = ActivityManager.shared

    // Current user's rank info
    private var myRank: (position: Int, total: Int)? {
        let uid = appState.currentUID
        guard !uid.isEmpty, group.isActive, group.hasStarted, !group.isCompleted else { return nil }
        let ranked = group.rankedMembers
        guard let idx = ranked.firstIndex(where: { $0.uid == uid }) else { return nil }
        return (idx + 1, ranked.count)
    }

    private var isInDangerZone: Bool {
        guard let rank = myRank else { return false }
        let threshold = max(1, rank.total * 2 / 3) // bottom third
        return rank.position > threshold
    }

    private var rankBadgeColor: Color {
        guard let rank = myRank else { return Theme.green }
        if isInDangerZone { return Theme.red }
        if rank.position <= 3 { return Theme.green }
        if rank.position <= 6 { return Theme.orange }
        return Theme.red
    }

    private var leader: Member? {
        guard group.isActive, group.hasStarted, !group.isCompleted else { return nil }
        return group.rankedMembers.first
    }

    // Last message in this group's chat
    private var lastMessage: ChatMessage? {
        let gid = group.id.uuidString
        return chatManager.messages
            .filter { $0.groupId == gid && !chatManager.deletedMessageIds.contains($0.id) }
            .last
    }

    /// Top 3 members sorted by rank (lowest screen time first)
    private var top3: [Member] {
        let ranked = group.rankedMembers
        return Array(ranked.prefix(3))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 16) {
                // TOP: Group name + progress
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(group.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            // Scope badge (subtle)
                            if group.scope == .apps && !group.trackedApps.isEmpty {
                                HStack(spacing: 3) {
                                    ForEach(group.trackedApps.prefix(3), id: \.self) { appId in
                                        if let app = AppDef.find(appId) {
                                            AppIconView(app: app, size: 16)
                                        }
                                    }
                                    if group.trackedApps.count > 3 {
                                        Text("+\(group.trackedApps.count - 3)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Theme.textFaint)
                                    }
                                }
                            } else if group.scope == .social {
                                Text(L10n.t("social").uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 2).padding(.horizontal, 6)
                                    .background(Theme.blue)
                                    .cornerRadius(4)
                            }
                        }
                        // Progress inline or status
                        if group.isPending {
                            Text("\(group.members.count)/\(group.requiredPlayers) \(L10n.t("signatures"))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.orange)
                        } else if !group.hasStarted {
                            Text(L10n.t("starts_midnight"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textMuted)
                        } else if group.isActive && !group.isCompleted {
                            HStack(spacing: 8) {
                                Text("Day \(group.duration.days - group.daysLeft)/\(group.duration.days)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.textFaint)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Theme.bgWarm)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Theme.text.opacity(0.5))
                                            .frame(width: geo.size.width * group.challengeProgress)
                                    }
                                }
                                .frame(height: 4)
                                Text("\(Int(group.challengeProgress * 100))%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.textFaint)
                            }
                        } else if group.isCompleted {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.green)
                                Text(L10n.t("challenge_complete"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.green)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                }

                // MIDDLE: Top 3 podium avatars (photo-centric hero)
                if group.isActive && group.hasStarted && !top3.isEmpty {
                    HStack(alignment: .bottom, spacing: 0) {
                        Spacer()
                        // #2 (left)
                        if top3.count > 1 {
                            cardPodiumMember(member: top3[1], rank: 2)
                        }
                        // #1 (center, bigger)
                        cardPodiumMember(member: top3[0], rank: 1)
                            .padding(.horizontal, 12)
                        // #3 (right)
                        if top3.count > 2 {
                            cardPodiumMember(member: top3[2], rank: 3)
                        }
                        Spacer()
                    }
                } else if !group.isActive || !group.hasStarted {
                    // Pre-start: show member avatars in a row
                    HStack(spacing: -8) {
                        ForEach(Array(group.members.prefix(6).enumerated()), id: \.offset) { i, member in
                            AvatarView(name: member.name, size: 40, color: Theme.textMuted,
                                       uid: member.uid, isMe: appState.isMe(member))
                                .environmentObject(appState)
                                .overlay(Circle().stroke(.ultraThinMaterial, lineWidth: 2))
                                .zIndex(Double(6 - i))
                        }
                        if group.members.count > 6 {
                            Text("+\(group.members.count - 6)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textFaint)
                                .padding(.leading, 12)
                        }
                    }
                }

                // BOTTOM: +X others + stake
                HStack(spacing: 6) {
                    if group.members.count > 3 && group.isActive && group.hasStarted {
                        Text("+\(group.members.count - 3) others")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textFaint)
                    } else if !group.isActive || !group.hasStarted {
                        Text("\(group.members.count) \(L10n.t("players_needed"))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textFaint)
                    }
                    if group.stake != "For fun" && !group.stake.isEmpty {
                        Text("·")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textFaint)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.orange)
                        Text(group.stake)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textFaint)
                }
            }
            .padding(18)

            // Rank badge (top-right)
            if let rank = myRank {
                ZStack {
                    Circle()
                        .fill(rankBadgeColor)
                        .frame(width: 40, height: 40)
                    Text("#\(rank.position)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: rankBadgeColor.opacity(0.4), radius: 6, x: 0, y: 2)
                .offset(x: -10, y: 10)
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.4))
        )
        .liquidGlass(cornerRadius: 20, style: .ultraThin)
        .overlay(
            isInDangerZone
                ? RoundedRectangle(cornerRadius: 20).stroke(Theme.red.opacity(0.3), lineWidth: 1.5)
                : nil
        )
        .shadow(color: Theme.text.opacity(0.08), radius: 10, x: 0, y: 2)
    }

    /// A single podium member cell for the GroupCard
    private func cardPodiumMember(member: Member, rank: Int) -> some View {
        let avatarSize: CGFloat = rank == 1 ? 64 : 52
        let mins = group.rankMinutes(member)
        return VStack(spacing: 4) {
            ZStack {
                if rank == 1 {
                    Circle()
                        .fill(Theme.green.opacity(0.12))
                        .frame(width: avatarSize + 8, height: avatarSize + 8)
                }
                AvatarView(name: member.name, size: avatarSize, color: rank == 1 ? Theme.green : Theme.textMuted,
                           uid: member.uid, isMe: appState.isMe(member))
                    .environmentObject(appState)
                    .overlay(
                        Circle()
                            .stroke(rank == 1 ? Theme.green : Theme.textFaint.opacity(0.3), lineWidth: rank == 1 ? 2.5 : 1.5)
                    )
            }
            Text(member.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Text(mins > 0 ? formatTime(mins) : "--")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(rank == 1 ? Theme.green : Theme.text)
            Text("#\(rank)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.textFaint)
        }
        .frame(width: rank == 1 ? 80 : 70)
    }

    private func ordinal(_ n: Int) -> String {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        if lang == "fr" {
            return n == 1 ? "1er" : "\(n)e"
        }
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}


// MARK: - FriendDetailView (Messages | Profile, swipable)

struct FriendDetailView: View {
    let friend: AppUser
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var activeTab: FriendTab = .messages

    enum FriendTab: String, CaseIterable {
        case messages, profile
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                Spacer()
                Text(friend.firstName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        // TODO: implement block via API
                        Log.d("[Block] User \(friend.id.prefix(8)) blocked")
                    } label: {
                        Label(L10n.t("block_user"), systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)

            // Tab pills
            HStack(spacing: 8) {
                ForEach(FriendTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                    }) {
                        Text(tab == .messages ? L10n.t("messages_tab") : L10n.t("profile_tab"))
                            .font(.system(size: 15, weight: activeTab == tab ? .semibold : .regular))
                            .foregroundColor(activeTab == tab ? Theme.bg : Theme.textMuted)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background {
                                if activeTab == tab {
                                    RoundedRectangle(cornerRadius: 20).fill(Theme.text)
                                } else {
                                    RoundedRectangle(cornerRadius: 20).fill(.clear).liquidGlass(cornerRadius: 20)
                                }
                            }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Swipable content
            TabView(selection: $activeTab) {
                ConversationView(friendUid: friend.id, friendName: friend.firstName, inline: true)
                    .environmentObject(appState)
                    .tag(FriendTab.messages)

                FriendProfileView(user: friend, inline: true)
                    .environmentObject(appState)
                    .tag(FriendTab.profile)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: activeTab)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

// MARK: - FriendRow

struct FriendRow: View {
    let friend: AppUser
    @EnvironmentObject var appState: AppState
    @ObservedObject private var chatManager = ActivityManager.shared

    private var lastMsg: ChatMessage? {
        chatManager.messagesWithFriend(friend.id).last
    }

    private var hasUnread: Bool {
        chatManager.hasUnreadMessages(from: friend.id)
    }

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(name: friend.firstName, size: 44, color: Theme.textMuted,
                       uid: friend.id, isMe: false)
                .environmentObject(appState)

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.firstName)
                    .font(.system(size: 16, weight: hasUnread ? .bold : .semibold))
                    .foregroundColor(Theme.text)
                if let msg = lastMsg {
                    Text(msg.isFromMe ? L10n.t("you") + ": \(msg.text ?? msg.activityTitle ?? "")" : (msg.text ?? msg.activityTitle ?? ""))
                        .font(.system(size: 13, weight: hasUnread ? .medium : .regular))
                        .foregroundColor(hasUnread ? Theme.text : Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let msg = lastMsg {
                Text(timeAgo(msg.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint)
            }

            if hasUnread {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 10, height: 10)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.4))
        )
        .liquidGlass(cornerRadius: 16, style: .ultraThin)
    }
}

// MARK: - JoinGroupSheet

struct JoinGroupSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var code      = ""
    @State private var isLoading = false
    @State private var errorMsg  : String? = nil
    @State private var joined    : Group?  = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let group = joined { successView(group) } else { entryView }
        }
    }

    var entryView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark").font(.system(size: 17)).foregroundColor(Theme.textMuted)
                }
                Spacer()
                Text(L10n.t("join_group")).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.textMuted)
                Spacer()
                Image(systemName: "xmark").opacity(0).font(.system(size: 17))
            }
            .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 40)

            Spacer()

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text(L10n.t("group_code"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textFaint)
                        .tracking(1.5).textCase(.uppercase)
                    TextField(L10n.t("group_code_placeholder"), text: $code)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .onChange(of: code) { v in code = v.uppercased(); errorMsg = nil }
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 40)
                }
                if let err = errorMsg {
                    Text(err).font(.system(size: 15)).foregroundColor(Theme.red).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            PrimaryButton(label: isLoading ? L10n.t("searching") : L10n.t("join")) {
                guard !isLoading else { return }
                Task { await doJoin() }
            }
            .padding(.horizontal, 24).padding(.bottom, 52)
            .opacity(code.count >= 8 && !isLoading ? 1 : 0.35)
            .disabled(code.count < 8 || isLoading)
        }
    }

    func successView(_ group: Group) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("✓")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(Theme.green)
                VStack(spacing: 10) {
                    Text(group.name).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.text)
                    Text(L10n.t("joined_group")).font(.system(size: 16)).foregroundColor(Theme.textMuted)
                }
            }
            Spacer()
            PrimaryButton(label: L10n.t("lets_go")) { isPresented = false }
                .padding(.horizontal, 24).padding(.bottom, 52)
        }
    }

    func doJoin() async {
        isLoading = true; errorMsg = nil
        let result = await appState.joinGroup(code: code)
        await MainActor.run {
            isLoading = false
            switch result {
            case .success(let g):
                joined = g
                PaktAnalytics.track(.groupJoined)
            case .alreadyMember:  errorMsg = L10n.t("already_in")
            case .error(let msg): errorMsg = msg == "group not found" ? L10n.t("group_not_found") : L10n.t("something_wrong")
            }
        }
    }
}
