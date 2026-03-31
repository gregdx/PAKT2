import SwiftUI
import Combine

// MARK: - FriendRequest

struct FriendRequest: Identifiable {
    var id      : String
    var fromId  : String
    var fromName: String
    var toId    : String
    var sentAt  : Date
}

// MARK: - FriendManager

final class FriendManager: ObservableObject {
    static let shared = FriendManager()

    @Published var friends         : [AppUser]       = [] {
        didSet { saveFriendsLocal() }
    }
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingIds     : Set<String>     = [] // UIDs auxquels on a déjà envoyé une demande
    @Published var errorMessage    : String?         = nil

    private var cancellables = Set<AnyCancellable>()
    private let friendsCacheKey = "pakt_friends_cache"

    init() { loadFriendsLocal() }

    private func loadFriendsLocal() {
        guard let data = UserDefaults.standard.data(forKey: friendsCacheKey),
              let decoded = try? JSONDecoder().decode([AppUser].self, from: data)
        else { return }
        friends = decoded
    }

    private func saveFriendsLocal() {
        guard let data = try? JSONEncoder().encode(friends) else { return }
        UserDefaults.standard.set(data, forKey: friendsCacheKey)
    }

    // MARK: - Start / Stop

    func startListening() {
        let uid = AuthManager.shared.currentUser?.id
            ?? UserDefaults.standard.string(forKey: UDKey.lastUID)
        guard let uid, !uid.isEmpty else { return }
        // Initial load via REST — ne jamais écraser le cache local avec une liste vide
        Task {
            if let apiFriends = try? await APIClient.shared.listFriends(), !apiFriends.isEmpty {
                await MainActor.run {
                    self.friends = apiFriends.map {
                        UsernameCache.store(uid: $0.userId, name: $0.username)
                        return AppUser(id: $0.userId, firstName: UsernameCache.resolve(uid: $0.userId, name: $0.username), email: "")
                    }
                }
            }
            if let requests = try? await APIClient.shared.listFriendRequests() {
                await MainActor.run {
                    self.incomingRequests = requests.map {
                        FriendRequest(id: $0.id, fromId: $0.fromId, fromName: $0.fromName, toId: $0.toId, sentAt: $0.sentAt)
                    }
                }
            }
        }

        // Listen to WebSocket events for real-time friend updates
        WebSocketManager.shared.onFriendRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let req = FriendRequest(id: event.requestId, fromId: event.fromId, fromName: event.fromName, toId: AuthManager.shared.currentUser?.id ?? "", sentAt: Date())
                if !self.incomingRequests.contains(where: { $0.id == req.id }) {
                    self.incomingRequests.append(req)
                }
            }
            .store(in: &cancellables)

        WebSocketManager.shared.onFriendAdded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let friend = AppUser(id: event.friendId, firstName: event.friendName ?? "", email: "")
                if !self.friends.contains(where: { $0.id == friend.id }) {
                    self.friends.append(friend)
                }
            }
            .store(in: &cancellables)

        WebSocketManager.shared.onFriendRemoved
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.friends.removeAll { $0.id == event.friendId }
            }
            .store(in: &cancellables)
    }

    func stopListening() {
        cancellables.removeAll()
    }

    // MARK: - Actions

    func sendRequest(to user: AppUser) {
        Task {
            do {
                try await APIClient.shared.sendFriendRequest(toID: user.id)
                await MainActor.run { self.outgoingIds.insert(user.id) }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func accept(_ req: FriendRequest) {
        Task {
            do {
                try await APIClient.shared.acceptFriendRequest(id: req.id)
                await MainActor.run { self.incomingRequests.removeAll { $0.id == req.id } }
                // Reload friends list
                if let friends = try? await APIClient.shared.listFriends() {
                    await MainActor.run {
                        self.friends = friends.map { AppUser(id: $0.userId, firstName: $0.username, email: "") }
                    }
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func decline(_ req: FriendRequest) {
        Task {
            do {
                try await APIClient.shared.declineFriendRequest(id: req.id)
                await MainActor.run { self.incomingRequests.removeAll { $0.id == req.id } }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func isFriend(_ uid: String) -> Bool {
        friends.contains { $0.id == uid }
    }

    func removeFriend(_ friendUid: String) {
        Task {
            do {
                try await APIClient.shared.removeFriend(uid: friendUid)
                await MainActor.run { self.friends.removeAll { $0.id == friendUid } }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }
}
