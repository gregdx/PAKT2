import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject var appState : AppState
    @ObservedObject private var invManager = InvitationManager.shared
    @Binding var selectedTab: Int
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showCreate   = false
    @State private var showJoin     = false
    @State private var showNotifs   = false
    @State private var isRefreshing = false

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
                        if appState.groups.isEmpty {
                            emptyState
                        } else {
                            groupsList
                        }
                        Spacer().frame(height: 100)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedGroupId) { gid in
                NavigationView {
                    GroupDetailView(groupId: gid, isSheet: true)
                        .environmentObject(appState)
                }
                .navigationViewStyle(.stack)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showCreate) {
                CreateGroupView().environmentObject(appState)
            }
            .sheet(isPresented: $showJoin) {
                JoinGroupSheet(isPresented: $showJoin).environmentObject(appState)
            }
            .sheet(isPresented: $showNotifs) {
                NotificationsView().environmentObject(appState)
            }
            .onAppear {
                Task { await appState.syncFromFirebase() }
                ScreenTimeManager.shared.syncToBackend(appState: appState)
            }
        }
    }

    // MARK: - Header

    var header: some View {
        HStack(alignment: .center) {
            Text(L10n.t("groups"))
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
            HStack(spacing: 8) {
                Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.textMuted)
                        .frame(width: 40, height: 40).liquidGlass(cornerRadius: 10)
                }
                .accessibilityLabel("Create group")
                Button(action: { showJoin = true }) {
                    Image(systemName: "link")
                        .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                        .frame(width: 40, height: 40).liquidGlass(cornerRadius: 10)
                }
                .accessibilityLabel("Join group")
                Button(action: { showNotifs = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                            .frame(width: 40, height: 40).liquidGlass(cornerRadius: 10)
                        if !invManager.pending.isEmpty {
                            Circle().fill(Theme.red).frame(width: 10, height: 10).offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Notifications")
                Button(action: { withAnimation { selectedTab = 3 } }) {
                    ZStack {
                        if let uiImage = appState.profileUIImage {
                            Image(uiImage: uiImage).resizable().scaledToFill()
                                .frame(width: 40, height: 40).clipShape(Circle())
                        } else {
                            Circle().fill(Theme.bgWarm).frame(width: 40, height: 40)
                            Text(String(appState.userName.prefix(1)).uppercased())
                                .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.textMuted)
                        }
                    }
                }
                .accessibilityLabel("Profile")
            }
        }
        .padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 28)
    }

    // MARK: - Empty state (first launch)

    var emptyState: some View {
        VStack(spacing: 24) {
            Text("👋")
                .font(.system(size: 56))
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
                    .liquidGlass(cornerRadius: 14)
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
                    .liquidGlass(cornerRadius: 14)
                }
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Groups list

    @State private var selectedGroupId: UUID? = nil

    var groupsList: some View {
        let uid = appState.currentUID
        let pendingGroups  = appState.groups.filter { $0.status == .pending }
        let activeGroups   = appState.groups.filter { $0.status == .active && !$0.isCompleted }
        let finishedGroups = appState.groups.filter { $0.status == .finished || $0.isCompleted }

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
                    Button(action: { selectedGroupId = group.id }) {
                        GroupCard(group: group, todayKey: todayKey)
                            .environmentObject(appState)
                    }
                    .buttonStyle(PlainButtonStyle())
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

    // MARK: - Create button (prominent, bottom)

    var createButton: some View {
        VStack(spacing: 12) {
            Button(action: { showCreate = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    Text(L10n.t("create_group")).font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .liquidGlass(cornerRadius: 14)
            }

            Button(action: { showJoin = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 16))
                    Text(L10n.t("join_group")).font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .liquidGlass(cornerRadius: 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}

// MARK: - GroupCard

struct GroupCard: View {
    let group: Group
    let todayKey: String
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header: name + mode badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)
                    HStack(spacing: 8) {
                        // Scope badge
                        if group.scope == .apps && !group.trackedApps.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(group.trackedApps.prefix(4), id: \.self) { appId in
                                    if let app = AppDef.find(appId) {
                                        AppIconView(app: app, size: 22)
                                    }
                                }
                                if group.trackedApps.count > 4 {
                                    Text("+\(group.trackedApps.count - 4)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Theme.textFaint)
                                }
                            }
                        } else if group.scope == .social {
                            Text(L10n.t("social").uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 3).padding(.horizontal, 8)
                                .background(Theme.blue)
                                .cornerRadius(6)
                        } else {
                            Text(L10n.t("scope_total").uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textFaint)
                                .padding(.vertical, 3).padding(.horizontal, 8)
                                .background(Theme.bgWarm)
                                .cornerRadius(6)
                        }
                        if group.isPending {
                            Text(L10n.t("status_pending"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.orange)
                                .padding(.vertical, 3).padding(.horizontal, 8)
                                .background(Theme.orange.opacity(0.08))
                                .cornerRadius(6)
                        } else if !group.hasStarted {
                            Text(L10n.t("starts_midnight"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.textMuted)
                                .padding(.vertical, 3).padding(.horizontal, 8)
                                .background(Theme.bgWarm)
                                .cornerRadius(6)
                        }
                    }
                }
                Spacer()
                if group.isPending {
                    VStack(spacing: 2) {
                        Text("\(group.members.count)/\(group.requiredPlayers)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.orange)
                        Text(L10n.t("signatures"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                    }
                } else if !group.hasStarted {
                    VStack(spacing: 2) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.textMuted)
                        Text("00:00")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textFaint)
                    }
                } else if !group.isCompleted {
                    VStack(spacing: 2) {
                        Text("\(group.daysLeft)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text(L10n.t(group.daysLeft == 0 ? "last_day" : "days_remaining"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                    }
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.green)
                }
            }

            // Members row
            HStack(spacing: -8) {
                if let groupPhoto = appState.loadGroupImage(for: group.id) {
                    Image(uiImage: groupPhoto)
                        .resizable().scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.trailing, 8)
                } else {
                    ForEach(Array(group.members.prefix(6).enumerated()), id: \.offset) { i, member in
                        AvatarView(name: member.name, size: 32, color: Theme.textMuted,
                                   uid: member.uid, isMe: appState.isMe(member))
                            .environmentObject(appState)
                            .overlay(
                                Circle()
                                    .stroke(.ultraThinMaterial, lineWidth: 2)
                            )
                            .zIndex(Double(6 - i))
                    }
                }
                if appState.loadGroupImage(for: group.id) == nil && group.members.count > 6 {
                    Text("+\(group.members.count - 6)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textFaint)
                        .padding(.leading, 14)
                }
                Spacer()
                Text("\(group.members.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textFaint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textFaint)
            }
        }
        .padding(20)
        .contentShape(Rectangle())
        .liquidGlass(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(group.scope == .social || group.scope == .apps
                        ? Theme.blue.opacity(0.4)
                        : Color.white.opacity(0.15),
                        lineWidth: group.scope == .social || group.scope == .apps ? 1.5 : 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
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
                    TextField("GRP-XXXX", text: $code)
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
            .padding(.horizontal, 28).padding(.bottom, 52)
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
                .padding(.horizontal, 28).padding(.bottom, 52)
        }
    }

    func doJoin() async {
        isLoading = true; errorMsg = nil
        let result = await appState.joinGroup(code: code)
        await MainActor.run {
            isLoading = false
            switch result {
            case .success(let g): joined = g
            case .alreadyMember:  errorMsg = L10n.t("already_in")
            case .error(let msg): errorMsg = msg == "group not found" ? L10n.t("group_not_found") : L10n.t("something_wrong")
            }
        }
    }
}
