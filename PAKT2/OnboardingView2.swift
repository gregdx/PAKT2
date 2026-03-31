import SwiftUI
import AuthenticationServices
import FamilyControls

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var firebase = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    // Steps: 0 = welcome, 1 = auth, 2 = walkthrough (new users only)
    @State private var step           = 0
    @State private var isSignIn       = false
    @State private var isNewUser      = false
    @State private var firstName      = ""
    @State private var email          = ""
    @State private var password       = ""
    @State private var usernameError  : String? = nil
    @State private var checkTask      : Task<Void, Never>? = nil
    @State private var acceptedTerms  = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if firebase.needsUsername {
                usernameStep
            } else if firebase.needsEmailVerification {
                emailVerificationStep
            } else {
                switch step {
                case 0:  welcomeStep
                case 1:  authStep
                default: walkthroughView
                }
            }
        }
        .transaction { t in
            if step != 1 { t.animation = .easeInOut(duration: 0.35) }
        }
        .onChange(of: firebase.isLoggedIn) { loggedIn in
            guard loggedIn, !firebase.needsEmailVerification, let user = firebase.currentUser else { return }
            proceedAfterAuth(user: user)
        }
        .onChange(of: firebase.needsEmailVerification) { needs in
            guard !needs, firebase.isLoggedIn, let user = firebase.currentUser else { return }
            proceedAfterAuth(user: user)
        }
    }

    private func proceedAfterAuth(user: AppUser) {
        let alreadyOnboarded = UserDefaults.standard.bool(forKey: "isOnboarded_\(user.id)")
        if isSignIn || alreadyOnboarded {
            appState.loadAccount(uid: user.id, firstName: user.firstName, goalHours: user.goalHours)
        } else {
            appState.userName = user.firstName
            appState.goalHours = user.goalHours
            UserDefaults.standard.set(user.id, forKey: UDKey.lastUID)
            let ud = UserDefaults(suiteName: "group.com.PAKT2")
            ud?.set(user.id, forKey: "currentUID")
            ud?.set(user.firstName, forKey: "currentUserName")
            ud?.synchronize()
            AuthManager.shared.keychainWrite(key: "pakt_uid", value: user.id)
            AuthManager.shared.keychainWrite(key: "pakt_username", value: user.firstName)
            isNewUser = true
            step = 2
        }
    }

    // MARK: - Welcome (simple)

    var welcomeStep: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 20) {
                    Text("PAKT")
                        .font(.system(size: 66, weight: .bold))
                        .foregroundColor(.black)
                    Text(L10n.t("tagline"))
                        .font(.system(size: 20))
                        .foregroundColor(Color.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                Spacer()
                VStack(spacing: 16) {
                    Button(action: { isSignIn = false; step = 1 }) {
                        Text(L10n.t("get_started"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Color.black).cornerRadius(14)
                    }
                    Button(action: { isSignIn = true; step = 1 }) {
                        Text(L10n.t("already_account"))
                            .font(.system(size: 15))
                            .foregroundColor(Color.black.opacity(0.4))
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 52)
            }
        }
    }

    // MARK: - Auth

    var authStep: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { step = 0 }) {
                    Image(systemName: "chevron.left").font(.system(size: 18)).foregroundColor(Theme.textMuted)
                }
                Spacer()
                Button(action: { isSignIn.toggle() }) {
                    Text(isSignIn ? L10n.t("create_instead") : L10n.t("sign_in_instead"))
                        .font(.system(size: 15)).foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 32)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    Text(isSignIn ? L10n.t("welcome_back") : L10n.t("create_account"))
                        .font(.system(size: 34, weight: .black)).foregroundColor(Theme.text)
                    if !isSignIn {
                        VStack(alignment: .leading, spacing: 4) {
                            AppField(label: L10n.t("username"), text: $firstName, uppercase: false)
                                .onChange(of: firstName) { val in
                                    // Forcer minuscules, pas d'espaces, caractères autorisés seulement
                                    let clean = val.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                                    if clean != val { firstName = clean }
                                    usernameError = nil
                                    checkTask?.cancel()
                                    guard clean.count >= 2 else { return }
                                    checkTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        guard !Task.isCancelled else { return }
                                        let available = await AuthManager.shared.isUsernameAvailable(clean)
                                        await MainActor.run {
                                            usernameError = available ? nil : L10n.t("username_taken")
                                        }
                                    }
                                }
                            if usernameError == nil && firstName.count >= 2 {
                                Text(L10n.t("available"))
                                    .font(.system(size: 13)).foregroundColor(Theme.green)
                            }
                            if let err = usernameError {
                                Text(err).font(.system(size: 13)).foregroundColor(Theme.red)
                            }
                        }
                    }
                    AppField(label: L10n.t("email"),    text: $email,    keyboard: .emailAddress)
                    AppField(label: L10n.t("password"), text: $password, secure: true)
                    if !isSignIn {
                        HStack(alignment: .top, spacing: 10) {
                            Button(action: { acceptedTerms.toggle() }) {
                                Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18))
                                    .foregroundColor(acceptedTerms ? Theme.text : Theme.textFaint)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                (Text(L10n.t("accept_terms_prefix"))
                                    .foregroundColor(Theme.textMuted) +
                                Text(L10n.t("terms_of_use"))
                                    .foregroundColor(Theme.text)
                                    .underline() +
                                Text(L10n.t("accept_terms_and"))
                                    .foregroundColor(Theme.textMuted) +
                                Text(L10n.t("privacy_policy"))
                                    .foregroundColor(Theme.text)
                                    .underline())
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                                    .onTapGesture {
                                        if let url = URL(string: "https://pakt-app.com/privacy") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                            }
                        }
                        .padding(.top, 4)
                    }
                    if let err = firebase.errorMessage {
                        Text(err).font(.system(size: 14)).foregroundColor(Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Buttons inside scroll so keyboard doesn't cover them
                    VStack(spacing: 14) {
                        PrimaryButton(label: firebase.isLoading ? L10n.t("loading") : (isSignIn ? L10n.t("sign_in") : L10n.t("continue"))) {
                            Task {
                                if isSignIn { await firebase.signIn(email: email, password: password) }
                                else        { await firebase.signUp(firstName: firstName, email: email, password: password) }
                            }
                        }
                        .opacity(canContinue ? 1 : 0.35)
                        .disabled(!canContinue || firebase.isLoading)

                        HStack(spacing: 12) {
                            Rectangle().fill(Theme.border).frame(height: 0.5)
                            Text("or").font(.system(size: 14)).foregroundColor(Theme.textFaint)
                            Rectangle().fill(Theme.border).frame(height: 0.5)
                        }

                        AppleSignInButton {
                            Task { await firebase.triggerAppleSignIn() }
                        }
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
    }

    var canContinue: Bool {
        isSignIn
            ? !email.isEmpty && password.count >= 6
            : !firstName.isEmpty && email.contains("@") && password.count >= 6 && usernameError == nil && acceptedTerms
    }

    // MARK: - Walkthrough (after account creation)

    @State private var wtPage = 0
    @State private var permissionError: String? = nil
    @ObservedObject private var stManager = ScreenTimeManager.shared

    private var wtPages: [(icon: String, titleKey: String, descKey: String, isPermission: Bool)] {[
        ("iphone",              "ob_time_title",      "ob_time_desc",      false),
        ("person.2.fill",       "ob_friends_title",   "ob_friends_desc",   false),
        ("trophy.fill",         "ob_challenge_title",  "ob_challenge_desc",  false),
        ("chart.bar.fill",      "ob_track_title",     "ob_track_desc",     false),
        ("clock.badge.checkmark", "screen_time_access", "screen_time_desc",  true),
    ]}

    var walkthroughView: some View {
        let currentPage = wtPages[wtPage]
        let isLast = currentPage.isPermission
        let totalPages = wtPages.count

        return ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip (not on permission page)
                HStack {
                    Spacer()
                    if !isLast {
                        Button(action: { withAnimation { wtPage = totalPages - 1 } }) {
                            Text(L10n.t("skip"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color.black.opacity(0.35))
                        }
                    }
                }
                .frame(height: 20)
                .padding(.horizontal, 28).padding(.top, 60)

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 120, height: 120)
                    Image(systemName: currentPage.icon)
                        .font(.system(size: 50, weight: .light))
                        .foregroundColor(.black)
                }
                .scaleEffect(1)
                .transition(.scale.combined(with: .opacity))
                .id("icon-\(wtPage)")
                .padding(.bottom, 40)

                // Title
                Text(L10n.t(currentPage.titleKey))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .id("title-\(wtPage)")
                    .transition(.asymmetric(
                        insertion: .offset(y: 20).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .padding(.bottom, 14)

                // Description
                Text(L10n.t(currentPage.descKey))
                    .font(.system(size: 18))
                    .foregroundColor(Color.black.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .id("desc-\(wtPage)")
                    .transition(.asymmetric(
                        insertion: .offset(y: 20).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .padding(.horizontal, 36)

                if isLast, let err = permissionError {
                    Text(err)
                        .font(.system(size: 14)).foregroundColor(Color.red)
                        .padding(.top, 12)
                }

                Spacer()
                Spacer()

                // Dots + button
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Capsule()
                                .fill(i == wtPage ? Color.black : Color.black.opacity(0.15))
                                .frame(width: i == wtPage ? 24 : 8, height: 8)
                                .animation(.easeInOut(duration: 0.25), value: wtPage)
                        }
                    }

                    if isLast {
                        // Permission page — action buttons
                        VStack(spacing: 14) {
                            Button(action: {
                                Task {
                                    await ScreenTimeManager.shared.requestAuthorization()
                                    // Finaliser même si refusé — les données backend suffisent en fallback
                                    finalizeOnboarding()
                                }
                            }) {
                                Text(L10n.t("allow_access"))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                                    .background(Color.black).cornerRadius(14)
                            }
                            Button(action: { finalizeOnboarding() }) {
                                Text(L10n.t("enter_manually"))
                                    .font(.system(size: 15))
                                    .foregroundColor(Color.black.opacity(0.35))
                            }
                        }
                    } else {
                        // Next button
                        Button(action: { withAnimation(.easeInOut(duration: 0.35)) { wtPage += 1 } }) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.black)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 52)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: wtPage)
        .onChange(of: scenePhase) { phase in
            if phase == .active && wtPage == wtPages.count - 1 {
                // Retour des Réglages — vérifier si l'accès a été accordé
                stManager.refreshAuthorizationStatus()
                if stManager.isAuthorized {
                    finalizeOnboarding()
                }
            }
        }
    }

    private func finalizeOnboarding() {
        if let user = firebase.currentUser {
            appState.loadAccount(uid: user.id, firstName: user.firstName, goalHours: user.goalHours)
        } else {
            appState.isOnboarded = true
        }
    }

    // MARK: - Username (after Apple Sign In)

    @State private var appleUsername = ""
    @State private var appleUsernameError: String? = nil
    @State private var appleCheckTask: Task<Void, Never>? = nil

    var usernameStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text(L10n.t("choose_username"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Theme.text)
                VStack(alignment: .leading, spacing: 8) {
                    AppField(label: L10n.t("username"), text: $appleUsername, uppercase: false)
                        .onChange(of: appleUsername) { val in
                            let clean = val.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                            if clean != val { appleUsername = clean }
                            appleUsernameError = nil
                            appleCheckTask?.cancel()
                            guard clean.count >= 2 else { return }
                            appleCheckTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                guard !Task.isCancelled else { return }
                                let available = await AuthManager.shared.isUsernameAvailable(clean)
                                await MainActor.run {
                                    appleUsernameError = available ? nil : L10n.t("username_taken")
                                }
                            }
                        }
                    if let err = appleUsernameError {
                        Text(err).font(.system(size: 13)).foregroundColor(Theme.red)
                    }
                    if let err = firebase.errorMessage {
                        Text(err).font(.system(size: 14)).foregroundColor(Theme.red)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            PrimaryButton(label: firebase.isLoading ? L10n.t("loading") : L10n.t("continue")) {
                Task { await firebase.finalizeAppleAccount(username: appleUsername) }
            }
            .opacity(appleUsername.count >= 2 && appleUsernameError == nil && !firebase.isLoading ? 1 : 0.35)
            .disabled(appleUsername.count < 2 || appleUsernameError != nil || firebase.isLoading)
            .padding(.horizontal, 32).padding(.bottom, 52)
        }
    }

    // MARK: - Email Verification (6-digit code)

    @State private var verificationCode = ""
    @State private var verificationChecking = false
    @State private var resendCooldown = 0

    var emailVerificationStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(Theme.text)

                VStack(spacing: 10) {
                    Text(L10n.t("verify_email"))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Theme.text)
                }

                if !email.isEmpty {
                    Text(email)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Theme.text)
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .liquidGlass(cornerRadius: 8)
                }

                // Code input
                TextField("000000", text: $verificationCode)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .onChange(of: verificationCode) { v in
                        verificationCode = String(v.filter { $0.isNumber }.prefix(6))
                    }
                Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 60)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                PrimaryButton(label: verificationChecking ? L10n.t("checking") : L10n.t("continue")) {
                    guard verificationCode.count == 6 else { return }
                    verificationChecking = true
                    Task {
                        await firebase.verifyEmail(code: verificationCode)
                        await MainActor.run { verificationChecking = false }
                    }
                }
                .opacity(verificationCode.count == 6 ? 1 : 0.35)
                .disabled(verificationCode.count != 6 || verificationChecking)

                Button(action: {
                    guard resendCooldown == 0 else { return }
                    Task { await firebase.resendVerificationEmail() }
                    resendCooldown = 30
                    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                        resendCooldown -= 1
                        if resendCooldown <= 0 { timer.invalidate() }
                    }
                }) {
                    Text(resendCooldown > 0 ? "\(L10n.t("resend_email")) (\(resendCooldown)s)" : L10n.t("resend_email"))
                        .font(.system(size: 15))
                        .foregroundColor(resendCooldown > 0 ? Theme.textFaint : Theme.textMuted)
                }

                if let err = firebase.errorMessage {
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.red)
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 52)
        }
    }
}

// MARK: - Apple Sign In Button

struct AppleSignInButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 20, weight: .medium))
                Text("Sign in with Apple")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(colorScheme == .dark ? Color.white : Color.black)
            .cornerRadius(12)
        }
    }
}
