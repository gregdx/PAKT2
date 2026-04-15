import SwiftUI

struct FriendProfileView: View {
    let user: AppUser
    var inline: Bool = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var unlockedIds: Set<String> = []
    @State private var isLoading = true
    @State private var memberSince: Date? = nil
    @State private var appearAnimation = false
    @State private var headerAnimation = false
    @State private var scrollOffset: CGFloat = 0
    @State private var tappedAchievementId: String?
    @State private var showingParticles: [String: Bool] = [:]
    @Namespace private var animation

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            
            // ScrollView avec détection de l'offset pour parallaxe
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !inline {
                            // Header
                            HStack {
                                Button(action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        dismiss()
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(Theme.textMuted)
                                }
                                .accessibilityLabel(L10n.t("done"))
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 56)
                            .padding(.bottom, 16)
                            .offset(y: scrollOffset * 0.3)
                        } else {
                            Spacer().frame(height: 16)
                        }

                        // Avatar + name avec effet parallaxe
                        AvatarView(name: user.firstName, size: 88, color: Theme.textMuted,
                                   uid: user.id, isMe: false)
                            .environmentObject(appState)
                            .scaleEffect(headerAnimation ? 1.0 : 0.5)
                            .opacity(headerAnimation ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: headerAnimation)
                            .offset(y: scrollOffset * 0.5) // Effet parallaxe
                            .scaleEffect(1.0 + min(max(scrollOffset, -100), 0) / 500) // Scale au scroll vers le haut

                        Text(user.firstName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.text)
                            .padding(.top, 12)
                            .opacity(headerAnimation ? 1.0 : 0.0)
                            .offset(y: headerAnimation ? 0 : 20)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: headerAnimation)
                            .offset(y: scrollOffset * 0.4)

                        if let since = memberSince {
                            Text(L10n.t("veteran") + " · " + since.formatted(.dateTime.month(.wide).year()))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textFaint)
                                .padding(.top, 4)
                                .opacity(headerAnimation ? 1.0 : 0.0)
                                .offset(y: headerAnimation ? 0 : 20)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: headerAnimation)
                                .offset(y: scrollOffset * 0.35)
                        }

                        if !user.bio.isEmpty {
                            Text(user.bio)
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                                .padding(.horizontal, 40)
                                .opacity(headerAnimation ? 1.0 : 0.0)
                                .offset(y: headerAnimation ? 0 : 20)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: headerAnimation)
                                .offset(y: scrollOffset * 0.25)
                        }

                        // Events the friend is attending — shown FIRST
                        FriendEventsSection(userId: user.id)
                            .padding(.top, 28)

                    // Achievements section removed per user request (April 12 2026)

                        Spacer().frame(height: 60)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self,
                                          value: geo.frame(in: .named("scroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation {
                headerAnimation = true
            }
        }
        .task {
            do {
                let profile = try await APIClient.shared.getUserProfile(uid: user.id)
                await MainActor.run {
                    unlockedIds = Set(profile.achievements)
                    memberSince = profile.memberSince
                    isLoading = false
                    
                    // Déclencher l'animation des médailles après un court délai
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appearAnimation = true
                    }
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}
// MARK: - Preference Key pour le scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Effet de particules
struct ParticleEffectView: View {
    let color: Color
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var opacity: Double
    }
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .scaleEffect(particle.scale)
                    .opacity(particle.opacity)
                    .offset(x: particle.x, y: particle.y)
            }
        }
        .onAppear {
            generateParticles()
        }
    }
    
    func generateParticles() {
        for _ in 0..<12 {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 20...40)
            
            let particle = Particle(
                x: cos(angle) * distance,
                y: sin(angle) * distance,
                scale: Double.random(in: 0.5...1.5),
                opacity: 0
            )
            
            particles.append(particle)
        }
        
        // Animer les particules
        withAnimation(.easeOut(duration: 0.6)) {
            for i in 0..<particles.count {
                particles[i].opacity = 1.0
            }
        }
        
        withAnimation(.easeIn(duration: 0.4).delay(0.2)) {
            for i in 0..<particles.count {
                particles[i].opacity = 0
                particles[i].scale *= 0.5
            }
        }
    }
}

