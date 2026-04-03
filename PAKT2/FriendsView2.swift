import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var appState   : AppState
    @StateObject private var fm       = FriendManager.shared
    @ObservedObject private var firebase = AuthManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var searchQuery       = ""
    @State private var hasLoadedContacts = false
    @State private var avatarCache       : [String: UIImage] = [:]
    @State private var friendToRemove   : AppUser? = nil

    var body: some View {
        NavigationView {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    if !fm.incomingRequests.isEmpty {
                        requestsSection
                        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24)
                    }

                    friendsSection
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24)
                    searchSection
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24)
                    contactsSection
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24)
                    inviteLinkSection
                    Spacer().frame(height: 60)
                }
            }
        }
        .navigationBarHidden(true)
        }
        .onAppear { /* listener démarré dans ContentView */ }
        .alert(L10n.t("remove"), isPresented: Binding(
            get: { friendToRemove != nil },
            set: { if !$0 { friendToRemove = nil } }
        )) {
            Button(L10n.t("cancel"), role: .cancel) { friendToRemove = nil }
            Button(L10n.t("remove"), role: .destructive) {
                if let f = friendToRemove { fm.removeFriend(f.id) }
                friendToRemove = nil
            }
        } message: {
            if let f = friendToRemove {
                Text("Remove \(f.firstName) from your friends?")
            }
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            Text(L10n.t("friends_title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").font(.system(size: 16)).foregroundColor(Theme.textMuted)
                    .frame(width: 36, height: 36).liquidGlass(cornerRadius: 10)
            }
        }
        .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 28)
    }

    // MARK: - Incoming requests

    var requestsSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: L10n.t("friend_requests"))
            VStack(spacing: 0) {
                ForEach(Array(fm.incomingRequests.enumerated()), id: \.element.id) { i, req in
                    HStack(spacing: 14) {
                        avatarView(uid: req.fromId, name: req.fromName, size: 40)
                        Text(req.fromName)
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        HStack(spacing: 8) {
                            Button(action: { fm.decline(req) }) {
                                Image(systemName: "xmark").font(.system(size: 14)).foregroundColor(Theme.textMuted)
                                    .frame(width: 36, height: 36).background(Theme.bgWarm).cornerRadius(10)
                            }
                            Button(action: { fm.accept(req) }) {
                                Image(systemName: "checkmark").font(.system(size: 14)).foregroundColor(Theme.green)
                                    .frame(width: 36, height: 36).background(Theme.green.opacity(0.1)).cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    if i < fm.incomingRequests.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 56)
                    }
                }
            }
            .liquidGlass(cornerRadius: 12)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Friends list

    var friendsSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: L10n.t("my_friends") + " (\(fm.friends.count))")
            if fm.friends.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("no_friends"))
                        .font(.system(size: 15)).foregroundColor(Theme.textFaint)
                    Text(L10n.t("search_or_invite"))
                        .font(.system(size: 13)).foregroundColor(Theme.textFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24).padding(.horizontal, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(fm.friends, id: \.id) { user in
                        NavigationLink(destination: FriendProfileView(user: user).environmentObject(appState)) {
                            HStack(spacing: 14) {
                                avatarView(uid: user.id, name: user.firstName, size: 40)
                                Text(user.firstName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textFaint)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .contentShape(Rectangle())
                            .liquidGlass(cornerRadius: 16)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) { friendToRemove = user } label: {
                                Label(L10n.t("remove"), systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Search

    var searchSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: L10n.t("find_username")).padding(.top, 20)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundColor(Theme.textFaint)
                    TextField(L10n.t("username_ph"), text: $searchQuery)
                        .font(.system(size: 17)).foregroundColor(Theme.text)
                        .autocapitalization(.none).disableAutocorrection(true)
                        .onChange(of: searchQuery) { val in
                            Task { await firebase.searchByUsername(val) }
                        }
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = ""; firebase.searchResults = [] }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textFaint)
                        }
                    }
                }
                .padding(16).liquidGlass(cornerRadius: 14)

                if !firebase.searchResults.isEmpty {
                    userList(firebase.searchResults)
                } else if !searchQuery.isEmpty {
                    Text(L10n.t("no_user_found"))
                        .font(.system(size: 15)).foregroundColor(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
    }

    // MARK: - Contacts

    var contactsSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: L10n.t("from_contacts")).padding(.top, 20)
            if firebase.matchedContacts.isEmpty && hasLoadedContacts {
                Text(L10n.t("no_contacts"))
                    .font(.system(size: 13)).foregroundColor(Theme.textFaint)
                    .padding(.horizontal, 24).padding(.bottom, 16)
            } else if !firebase.matchedContacts.isEmpty {
                userList(firebase.matchedContacts).padding(.horizontal, 24)
            } else {
                Button(action: { hasLoadedContacts = true; Task { await firebase.matchContacts() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 14))
                        Text(L10n.t("find_contacts"))
                    }
                    .font(.system(size: 14)).foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .liquidGlass(cornerRadius: 10)
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
    }

    // MARK: - Invite link

    var inviteLinkSection: some View {
        VStack(spacing: 0) {
            SectionTitle(text: L10n.t("invite_friend")).padding(.top, 20)
            Button(action: {
                let code = appState.groups.first?.code ?? "PAKT"
                UIPasteboard.general.string = "Join me on PAKT! Download the app and enter my group code: \(code)"
            }) {
                HStack(spacing: 14) {
                    Image(systemName: "link").font(.system(size: 17)).foregroundColor(Theme.textMuted)
                    Text(L10n.t("copy_invite")).font(.system(size: 17, weight: .medium)).foregroundColor(Theme.text)
                    Spacer()
                    Image(systemName: "doc.on.doc").font(.system(size: 15)).foregroundColor(Theme.textFaint)
                }
                .padding(18).liquidGlass(cornerRadius: 14)
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
    }

    // MARK: - User list

    func userList(_ users: [AppUser]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(users.enumerated()), id: \.element.id) { i, user in
                HStack(spacing: 14) {
                    avatarView(uid: user.id, name: user.firstName, size: 40)
                    Text(user.firstName).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    addFriendButton(user)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                if i < users.count - 1 {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 60)
                }
            }
        }
        .liquidGlass(cornerRadius: 14)
    }

    @ViewBuilder
    func addFriendButton(_ user: AppUser) -> some View {
        if fm.isFriend(user.id) {
            Text(L10n.t("friends_check"))
                .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.green)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .background(Theme.green.opacity(0.08)).cornerRadius(8)
        } else if fm.outgoingIds.contains(user.id) {
            Text(L10n.t("request_sent"))
                .font(.system(size: 14)).foregroundColor(Theme.textFaint)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .liquidGlass(cornerRadius: 8)
        } else {
            Button(action: { fm.sendRequest(to: user) }) {
                Text(L10n.t("add_friend_btn"))
                    .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.textMuted)
                    .padding(.vertical, 7).padding(.horizontal, 14)
                    .liquidGlass(cornerRadius: 10)
            }
        }
    }

    func avatarView(uid: String, name: String, size: CGFloat = 36) -> some View {
        ZStack {
            Circle().fill(Theme.bgWarm).frame(width: size, height: size)
            if let img = avatarCache[uid] {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.39, weight: .bold)).foregroundColor(Theme.textMuted)
            }
        }
        .onAppear {
            guard avatarCache[uid] == nil else { return }
            Task {
                if let img = await AuthManager.shared.fetchProfilePhoto(uid: uid) {
                    await MainActor.run { avatarCache[uid] = img }
                }
            }
        }
    }
}
