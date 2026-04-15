import SwiftUI
import Combine
import AuthenticationServices
import Contacts
import CryptoKit

// MARK: - AuthManager

class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var currentUser: AppUser? = nil
    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var needsEmailVerification: Bool = false
    @Published var needsUsername: Bool = false
    @Published var matchedContacts: [AppUser] = []
    @Published var searchResults: [AppUser] = []

    private(set) var accessToken: String?
    private(set) var refreshTokenValue: String?
    private(set) var extensionToken: String?
    private var nonce = ""
    private var appleSignInController: ASAuthorizationController?
    private var appleSignInDelegate: AppleSignInDelegate2?

    private let keychainGroup = AppConfig.keychainGroup
    private let kAppGroupID = AppConfig.appGroupID

    init() {
        // Restore tokens from Keychain
        accessToken = keychainRead(key: "pakt_access_token")
        refreshTokenValue = keychainRead(key: "pakt_refresh_token")
        extensionToken = keychainRead(key: "pakt_extension_token")

        // Restore cached user IMMEDIATELY (offline-first)
        if let userData = UserDefaults.standard.data(forKey: "pakt_cached_user"),
           let user = try? JSONDecoder().decode(AppUser.self, from: userData) {
            self.currentUser = user
            self.isLoggedIn = true
            Log.d("[AUTH] Restored cached user: \(user.id) \(user.firstName)")
        }

        if refreshTokenValue != nil {
            Task {
                let refreshed = await refreshTokens()
                if refreshed {
                    await loadCurrentUser()
                } else if self.currentUser == nil {
                    // Refresh failed AND no cached user → session is dead, force re-login
                    Log.d("[AUTH] Refresh failed with no cached user — forcing sign out")
                    await MainActor.run {
                        AppState.shared.signOut()
                    }
                }
                // If refresh fails but cached user exists → keep offline mode
            }
        }
    }

    // MARK: - Sign Up

    func signUp(firstName: String, email: String, password: String) async {
        guard !isLoading else { Log.d("[AUTH] signUp blocked — already loading"); return }
        await MainActor.run { isLoading = true; errorMessage = nil }
        Log.d("[AUTH] signUp starting for \(email)")

        do {
            let capitalized = firstName.prefix(1).uppercased() + firstName.dropFirst()
            let response = try await APIClient.shared.signUp(
                username: capitalized,
                email: email,
                password: password
            )
            Log.d("[AUTH] signUp success: \(response.user.id)")
            saveTokens(response)
            let user = response.user.toAppUser()
            shareUserInfoWithExtension(user)

            // TODO: Re-enable email verification when Resend domain is configured
            // let needsVerif = response.needsVerification ?? false
            let needsVerif = false
            await MainActor.run {
                self.currentUser = user
                self.needsEmailVerification = needsVerif
                self.isLoggedIn = true
                self.isLoading = false
                AppState.shared.loadAccount(uid: user.id, firstName: user.firstName, goalHours: user.goalHours)
            }
        } catch let error as APIClient.APIError {
            await MainActor.run { self.errorMessage = error.message; self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        guard !isLoading else { Log.d("[AUTH] signIn blocked — already loading"); return }
        await MainActor.run { isLoading = true; errorMessage = nil }
        Log.d("[AUTH] signIn starting for \(email)")

        do {
            let response = try await APIClient.shared.signIn(email: email, password: password)
            Log.d("[AUTH] signIn success: \(response.user.id)")
            saveTokens(response)
            let user = response.user.toAppUser()
            shareUserInfoWithExtension(user)

            // TODO: Re-enable email verification when Resend domain is configured
            await MainActor.run {
                self.currentUser = user
                self.needsEmailVerification = false
                self.isLoggedIn = true
                self.isLoading = false
                AppState.shared.loadAccount(uid: user.id, firstName: user.firstName, goalHours: user.goalHours)
            }
        } catch let error as APIClient.APIError {
            await MainActor.run { self.errorMessage = error.message; self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    // MARK: - Apple Sign In

    func triggerAppleSignIn() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        nonce = randomNonceString()

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let delegate = AppleSignInDelegate2 { [weak self] authorization in
            Task { await self?.handleAppleSignIn(authorization: authorization) }
        } onError: { [weak self] error in
            Log.d("[AUTH] Apple Sign In error: \(error)")
            Task { @MainActor in
                self?.errorMessage = error.localizedDescription
                self?.isLoading = false
            }
        }

        // Store references so they don't get deallocated before callback
        self.appleSignInDelegate = delegate

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        let context = AppleSignInPresentationContext2()
        controller.presentationContextProvider = context
        self.appleSignInController = controller

        controller.performRequests()
    }

    func handleAppleSignIn(authorization: ASAuthorization) async {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleCredential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            await MainActor.run { self.errorMessage = "Apple Sign In failed"; self.isLoading = false }
            return
        }

        let fullName = [appleCredential.fullName?.givenName, appleCredential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        do {
            let response = try await APIClient.shared.appleSignIn(identityToken: identityToken, fullName: fullName)
            saveTokens(response)
            let user = response.user.toAppUser()
            shareUserInfoWithExtension(user)

            await MainActor.run {
                self.currentUser = user
                self.needsUsername = response.needsUsername ?? false
                self.isLoggedIn = true
                self.isLoading = false
            }
        } catch let error as APIClient.APIError {
            await MainActor.run { self.errorMessage = error.message; self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    func finalizeAppleAccount(username: String) async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let response = try await APIClient.shared.appleFinalize(username: username)
            let user = response.user.toAppUser()
            shareUserInfoWithExtension(user)
            await MainActor.run {
                self.currentUser = user
                self.needsUsername = false
                self.isLoading = false
            }
        } catch let error as APIClient.APIError {
            await MainActor.run { self.errorMessage = error.message; self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    // MARK: - Email Verification

    func verifyEmail(code: String) async {
        do {
            let response = try await APIClient.shared.verifyEmail(code: code)
            if response.verified {
                await MainActor.run {
                    self.needsEmailVerification = false
                    if let user = self.currentUser {
                        AppState.shared.loadAccount(uid: user.id, firstName: user.firstName, goalHours: user.goalHours)
                    }
                }
            } else {
                await MainActor.run { self.errorMessage = L10n.t("email_not_verified") }
            }
        } catch {
            Log.d("[AUTH] verifyEmail error: \(error)")
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    func resendVerificationEmail() async {
        try? await APIClient.shared.resendVerification()
    }

    // MARK: - Token Management

    private var isRefreshing = false
    private var refreshResult: Bool? = nil

    func refreshTokens() async -> Bool {
        // Prevent concurrent refresh calls — wait for the in-flight one
        if isRefreshing {
            // Spin-wait for the ongoing refresh to complete
            while isRefreshing { try? await Task.sleep(nanoseconds: 50_000_000) }
            return refreshResult ?? false
        }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let rt = refreshTokenValue else { refreshResult = false; return false }
        do {
            let response = try await APIClient.shared.refreshToken(rt)
            accessToken = response.accessToken
            refreshTokenValue = response.refreshToken
            extensionToken = response.extensionToken
            keychainWrite(key: "pakt_access_token", value: response.accessToken)
            keychainWrite(key: "pakt_refresh_token", value: response.refreshToken)
            keychainWrite(key: "pakt_extension_token", value: response.extensionToken)
            refreshResult = true
            return true
        } catch {
            refreshResult = false
            return false
        }
    }

    func refreshExtensionToken() {
        // L'extension token est refresh a chaque refreshTokens() — ici on force juste un re-write
        if let t = extensionToken {
            keychainWrite(key: "pakt_extension_token", value: t)
        }
    }

    // MARK: - Sign Out

    @MainActor
    func signOut() {
        clearTokens()
        self.currentUser = nil
        self.isLoggedIn = false
        self.needsEmailVerification = false
        self.needsUsername = false
        FriendManager.shared.stopListening()
    }

    // MARK: - Delete / Pause

    func deleteAccount() async throws {
        try await APIClient.shared.deleteAccount()
        signOut()
    }

    func pauseAccount() async throws {
        try await APIClient.shared.pauseAccount()
        signOut()
    }

    // MARK: - User Data

    func loadCurrentUser() async {
        Log.d("[AUTH] loadCurrentUser starting...")
        do {
            let apiUser = try await APIClient.shared.getMe()
            let user = apiUser.toAppUser()
            Log.d("[AUTH] loadCurrentUser success: \(user.id) \(user.firstName)")
            shareUserInfoWithExtension(user)
            // Cache user locally for offline-first
            if let data = try? JSONEncoder().encode(user) {
                UserDefaults.standard.set(data, forKey: "pakt_cached_user")
            }
            await MainActor.run {
                self.currentUser = user
                self.isLoggedIn = true
            }
        } catch {
            Log.d("[AUTH] loadCurrentUser FAILED: \(error)")
            // Don't clear currentUser — keep cached version for offline use
        }
    }

    func isUsernameAvailable(_ username: String) async -> Bool {
        // Search for the username — if no results match exactly, it's available
        guard let results = try? await APIClient.shared.searchUsers(query: username) else { return true }
        let lower = username.lowercased()
        return !results.contains { $0.username.lowercased() == lower }
    }

    func updateGoal(hours: Double) async {
        _ = try? await APIClient.shared.updateMe(goalHours: hours)
        await MainActor.run { self.currentUser?.goalHours = hours }
    }

    func updateUsername(_ newName: String) async throws {
        let user = try await APIClient.shared.updateMe(username: newName)
        let appUser = user.toAppUser()
        await MainActor.run { self.currentUser = appUser }
    }

    func uploadProfilePhoto(_ image: UIImage) async throws {
        guard let data = image.jpegData(compressionQuality: 0.5) else { return }
        let base64 = data.base64EncodedString()
        try await APIClient.shared.uploadPhoto(base64: base64)
    }

    func fetchProfilePhoto(uid: String) async -> UIImage? {
        do {
            let response = try await APIClient.shared.getPhoto(uid: uid)
            guard !response.photoBase64.isEmpty else {
                Log.d("[Photo] Empty photoBase64 for uid=\(uid.prefix(8))")
                return nil
            }
            guard let data = Data(base64Encoded: response.photoBase64) else {
                Log.d("[Photo] Base64 decode failed for uid=\(uid.prefix(8))")
                return nil
            }
            guard let img = UIImage(data: data) else {
                Log.d("[Photo] UIImage decode failed for uid=\(uid.prefix(8))")
                return nil
            }
            return img
        } catch {
            Log.d("[Photo] Fetch failed for uid=\(uid.prefix(8)): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Search

    func searchByUsername(_ query: String) async {
        guard let results = try? await APIClient.shared.searchUsers(query: query) else { return }
        let users = results.map { $0.toAppUser() }
        await MainActor.run { self.searchResults = users }
    }

    func searchByEmail(_ email: String) async {
        guard let results = try? await APIClient.shared.searchUsers(query: email) else { return }
        let users = results.map { $0.toAppUser() }
        await MainActor.run { self.searchResults = users }
    }

    func matchContacts() async {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return }
            let keys = [CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var emails: [String] = []
            try store.enumerateContacts(with: request) { contact, _ in
                for email in contact.emailAddresses {
                    emails.append(email.value as String)
                }
            }
            guard !emails.isEmpty else { return }
            let results = try await APIClient.shared.matchContacts(emails: emails)
            let users = results.map { $0.toAppUser() }
            await MainActor.run { self.matchedContacts = users }
        } catch {
            Log.e("[AUTH] matchContacts error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func saveTokens(_ response: APIClient.AuthResponse) {
        accessToken = response.accessToken
        refreshTokenValue = response.refreshToken
        extensionToken = response.extensionToken
        keychainWrite(key: "pakt_access_token", value: response.accessToken)
        keychainWrite(key: "pakt_refresh_token", value: response.refreshToken)
        keychainWrite(key: "pakt_extension_token", value: response.extensionToken)
    }

    private func clearTokens() {
        accessToken = nil
        refreshTokenValue = nil
        extensionToken = nil
        // Tokens
        keychainDelete(key: "pakt_access_token")
        keychainDelete(key: "pakt_refresh_token")
        keychainDelete(key: "pakt_extension_token")
        // User info partagé avec l'extension
        keychainDelete(key: "pakt_uid")
        keychainDelete(key: "pakt_username")
        keychainDelete(key: "pakt_socialGoal")
        // Cached user
        UserDefaults.standard.removeObject(forKey: "pakt_cached_user")
        // App Group
        let ud = UserDefaults(suiteName: kAppGroupID)
        ud?.removeObject(forKey: "currentUID")
        ud?.removeObject(forKey: "currentUserName")
        ud?.removeObject(forKey: "goalMinutes")
        ud?.removeObject(forKey: "socialGoalMinutes")
        ud?.synchronize()
    }

    func shareUserInfoWithExtension(_ user: AppUser) {
        // App Group UD
        let ud = UserDefaults(suiteName: kAppGroupID)
        ud?.set(user.id, forKey: "currentUID")
        ud?.set(user.firstName, forKey: "currentUserName")
        ud?.synchronize()
        // Keychain (fallback)
        keychainWrite(key: "pakt_uid", value: user.id)
        keychainWrite(key: "pakt_username", value: user.firstName)
    }

    // MARK: - Keychain

    func keychainWrite(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainGroup
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func keychainRead(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: keychainGroup
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Apple Sign In Helpers

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms {
                if remaining == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - APIUser → AppUser Conversion

extension APIClient.APIUser {
    func toAppUser() -> AppUser {
        var user = AppUser(id: id, firstName: username, email: email, goalHours: goalHours)
        user.bio = bio
        user.memberSince = memberSince
        user.emailVerified = emailVerified
        user.medals = medals.map { medal in
            Medal(id: medal.id, groupName: medal.groupName, date: medal.date, mode: medal.mode, avgMinutes: medal.avgMinutes, goalMinutes: medal.goalMinutes)
        }
        return user
    }
}

// MARK: - Apple Sign In Delegates

class AppleSignInDelegate2: NSObject, ASAuthorizationControllerDelegate {
    let onSuccess: (ASAuthorization) -> Void
    let onError: (Error) -> Void

    init(onSuccess: @escaping (ASAuthorization) -> Void, onError: @escaping (Error) -> Void) {
        self.onSuccess = onSuccess
        self.onError = onError
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onSuccess(authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onError(error)
    }
}

class AppleSignInPresentationContext2: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Apple Sign In is triggered from foreground UI, so a window scene
        // always exists. We preconditon on that instead of falling back to
        // the deprecated `UIWindow()` initialiser.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            preconditionFailure("Apple Sign In anchor requested with no active UIWindowScene")
        }
        return scene.windows.first ?? UIWindow(windowScene: scene)
    }
}
