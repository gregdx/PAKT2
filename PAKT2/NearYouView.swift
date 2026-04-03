import SwiftUI

// MARK: - Venue model

struct Venue: Identifiable {
    let id = UUID()
    let name: String
    let category: VenueCategory
    let address: String
    let distance: Double // km
    let rating: Double
    let reviewCount: Int
    let websiteURL: String
    let gradient: [Color] // placeholder for photo
    let icon: String
    let tagline: String
}

enum VenueCategory: String, CaseIterable {
    case fitness = "Fitness"
    case cafe = "Café"
    case outdoor = "Outdoor"
    case wellness = "Wellness"
    case sport = "Sport"

    var icon: String {
        switch self {
        case .fitness:  return "figure.run"
        case .cafe:     return "cup.and.saucer.fill"
        case .outdoor:  return "leaf.fill"
        case .wellness: return "sparkles"
        case .sport:    return "sportscourt.fill"
        }
    }
}

// MARK: - Sample venues

extension Venue {
    static let all: [Venue] = [
        Venue(name: "Le Flore",
              category: .cafe,
              address: "Av. de Flore 3, 1000 Bruxelles",
              distance: 2.4,
              rating: 4.3,
              reviewCount: 1240,
              websiteURL: "https://leflore.brussels",
              gradient: [Color(red: 0.85, green: 0.65, blue: 0.45), Color(red: 0.65, green: 0.40, blue: 0.25)],
              icon: "cup.and.saucer.fill",
              tagline: "Bar · Brunch · Bois de la Cambre"),
        Venue(name: "Syncycle",
              category: .fitness,
              address: "Rue Lesbroussart 64, 1050 Ixelles",
              distance: 1.1,
              rating: 4.8,
              reviewCount: 187,
              websiteURL: "https://www.syncycle.be",
              gradient: [Color(red: 0.20, green: 0.20, blue: 0.35), Color(red: 0.35, green: 0.25, blue: 0.55)],
              icon: "figure.indoor.cycle",
              tagline: "Indoor cycling studio"),
        Venue(name: "Bois de la Cambre",
              category: .outdoor,
              address: "1000 Bruxelles",
              distance: 2.0,
              rating: 4.7,
              reviewCount: 3420,
              websiteURL: "https://www.visit.brussels/fr/visitors/venue-details.Bois-de-la-Cambre.17411",
              gradient: [Color(red: 0.15, green: 0.45, blue: 0.25), Color(red: 0.08, green: 0.30, blue: 0.18)],
              icon: "leaf.fill",
              tagline: "Park · Run · Walk · Lake"),
        Venue(name: "Basic-Fit Ixelles",
              category: .fitness,
              address: "Chaussée d'Ixelles 227, 1050 Ixelles",
              distance: 0.8,
              rating: 4.0,
              reviewCount: 312,
              websiteURL: "https://www.basic-fit.com",
              gradient: [Color(red: 0.90, green: 0.50, blue: 0.15), Color(red: 0.75, green: 0.30, blue: 0.10)],
              icon: "dumbbell.fill",
              tagline: "Gym · 24/7"),
        Venue(name: "Padel Brussels",
              category: .sport,
              address: "Av. du Racing 1, 1050 Ixelles",
              distance: 1.8,
              rating: 4.5,
              reviewCount: 245,
              websiteURL: "https://www.padelbrussels.be",
              gradient: [Color(red: 0.25, green: 0.35, blue: 0.55), Color(red: 0.15, green: 0.20, blue: 0.40)],
              icon: "sportscourt.fill",
              tagline: "Padel · Tennis · Squash"),
        Venue(name: "Aspria Royal La Rasante",
              category: .wellness,
              address: "Rue Sombre 56, 1200 Woluwe-Saint-Lambert",
              distance: 4.5,
              rating: 4.6,
              reviewCount: 890,
              websiteURL: "https://www.aspria.com/en/clubs/aspria-royal-la-rasante",
              gradient: [Color(red: 0.55, green: 0.40, blue: 0.60), Color(red: 0.35, green: 0.22, blue: 0.45)],
              icon: "sparkles",
              tagline: "Spa · Pool · Gym · Wellness"),
    ]
}

// MARK: - NearYouView

struct NearYouView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fm = FriendManager.shared

    @State private var selectedCategory: VenueCategory? = nil
    @State private var radiusKm: Double = 5.0
    @State private var showRadiusPicker = false
    @State private var inviteFriend: Venue? = nil
    @State private var appeared = false

    private var filteredVenues: [Venue] {
        Venue.all.filter { venue in
            venue.distance <= radiusKm
            && (selectedCategory == nil || venue.category == selectedCategory)
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    radiusSelector
                    categoryPills
                    venuesList
                    Spacer().frame(height: 100)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
        .sheet(item: $inviteFriend) { venue in
            InviteFriendSheet(venue: venue, friends: fm.friends)
                .environmentObject(appState)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(L10n.t("near_you_title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - Radius selector

    private var radiusSelector: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showRadiusPicker.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 14))
                    Text("\(Int(radiusKm)) km")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: showRadiusPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Theme.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .liquidGlass(cornerRadius: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, showRadiusPicker ? 12 : 16)

            if showRadiusPicker {
                VStack(spacing: 4) {
                    Slider(value: $radiusKm, in: 1...20, step: 1)
                        .tint(Theme.text)
                    HStack {
                        Text("1 km").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                        Spacer()
                        Text("20 km").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Category pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(label: L10n.t("all"), icon: nil, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(VenueCategory.allCases, id: \.self) { cat in
                    pill(label: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
    }

    private func pill(label: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12))
                }
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? Theme.bg : Theme.textMuted)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(isSelected ? Theme.text : Color.clear)
            .cornerRadius(20)
            .liquidGlass(cornerRadius: isSelected ? 0 : 20)
        }
    }

    // MARK: - Venues list

    private var venuesList: some View {
        VStack(spacing: 14) {
            if filteredVenues.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("no_venues_radius"))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 60)
            } else {
                ForEach(filteredVenues) { venue in
                    venueCard(venue)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Venue card

    private func venueCard(_ venue: Venue) -> some View {
        VStack(spacing: 0) {
            // Photo placeholder with gradient
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 140)
                    .overlay(
                        Image(systemName: venue.icon)
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.white.opacity(0.2))
                    )

                // Distance badge
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                    Text(String(format: "%.1f km", venue.distance))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(venue.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text(venue.tagline)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    // Rating
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.orange)
                        Text(String(format: "%.1f", venue.rating))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text("(\(venue.reviewCount))")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textFaint)
                    }
                }

                // Address
                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                    Text(venue.address)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textFaint)
                        .lineLimit(1)
                }

                // Action buttons
                HStack(spacing: 10) {
                    // Website
                    Button(action: {
                        if let url = URL(string: venue.websiteURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "safari")
                                .font(.system(size: 13))
                            Text(L10n.t("visit_website"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .liquidGlass(cornerRadius: 10)
                    }

                    // Invite a friend
                    Button(action: { inviteFriend = venue }) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 13))
                            Text(L10n.t("go_with_friend"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.text)
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - Invite friend sheet

struct InviteFriendSheet: View {
    let venue: Venue
    let friends: [AppUser]
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = ActivityManager.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16)).foregroundColor(Theme.textMuted)
                            .frame(width: 36, height: 36).liquidGlass(cornerRadius: 10)
                    }
                    Spacer()
                    Text(L10n.t("go_with_friend"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 16)

                // Venue preview
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                        Image(systemName: venue.icon)
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(venue.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text(venue.tagline)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.bottom, 24)

                // Friends list
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(friends) { friend in
                            Button(action: {
                                let activity = Activity(
                                    emoji: "📍",
                                    titleEN: venue.name, titleFR: venue.name,
                                    subtitleEN: venue.address, subtitleFR: venue.address,
                                    category: .outdoor, people: "2"
                                )
                                manager.sendActivity(activity, toFriendId: friend.id)
                                dismiss()
                            }) {
                                HStack(spacing: 14) {
                                    AvatarView(name: friend.firstName, size: 44, color: Theme.textMuted,
                                               uid: friend.id, isMe: false).environmentObject(appState)
                                    Text(friend.firstName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.textFaint)
                                }
                                .padding(.horizontal, 18).padding(.vertical, 14)
                                .liquidGlass(cornerRadius: 16)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
