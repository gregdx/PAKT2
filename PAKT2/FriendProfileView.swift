import SwiftUI

struct FriendProfileView: View {
    let user: AppUser
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var unlockedIds: Set<String> = []
    @State private var isLoading = true
    @State private var memberSince: Date? = nil

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 16)

                    // Avatar + name
                    AvatarView(name: user.firstName, size: 88, color: Theme.textMuted,
                               uid: user.id, isMe: false)
                        .environmentObject(appState)

                    Text(user.firstName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                        .padding(.top, 12)

                    if let since = memberSince {
                        Text(L10n.t("veteran") + " · " + since.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textFaint)
                            .padding(.top, 4)
                    }

                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .padding(.horizontal, 40)
                    }

                    // Achievements grid
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(text: L10n.t("medals"))
                            .padding(.horizontal, 24)

                        if isLoading {
                            HStack { Spacer(); ProgressView().tint(Theme.textFaint); Spacer() }
                                .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                ForEach(AchievementDef.all) { achievement in
                                    let unlocked = unlockedIds.contains(achievement.id)
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(unlocked ? achievement.color.opacity(0.15) : Theme.bgWarm)
                                                .frame(width: 44, height: 44)
                                            Image(systemName: achievement.icon)
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(unlocked ? achievement.color : Theme.textFaint)
                                        }
                                        Text(achievement.name)
                                            .font(.system(size: 12, weight: unlocked ? .semibold : .regular))
                                            .foregroundColor(unlocked ? Theme.text : Theme.textFaint)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .frame(height: 30)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .opacity(unlocked ? 1.0 : 0.4)
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        // Count
                        let count = unlockedIds.count
                        let total = AchievementDef.all.count
                        Text("\(count)/\(total)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .padding(.top, 28)

                    Spacer().frame(height: 60)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            do {
                let profile = try await APIClient.shared.getUserProfile(uid: user.id)
                await MainActor.run {
                    unlockedIds = Set(profile.achievements)
                    memberSince = profile.memberSince
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}
