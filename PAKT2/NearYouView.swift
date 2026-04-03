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
    let instagramHandle: String
    let photoURL: String // remote image
    let gradient: [Color] // fallback gradient
    let icon: String
    let tagline: String
    let description: String
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
              instagramHandle: "leflore.brussels",
              photoURL: "https://wp.localguide.brussels/wp-content/uploads/2025/01/Le-Flore-1500x900.webp",
              gradient: [Color(red: 0.85, green: 0.65, blue: 0.45), Color(red: 0.65, green: 0.40, blue: 0.25)],
              icon: "cup.and.saucer.fill",
              tagline: "Bar · Brunch · Bois de la Cambre",
              description: "A trendy guinguette in the heart of the Bois de la Cambre. Cocktails, brunch, tapas — the perfect spot to hang out with friends instead of scrolling. Open weekends with a retro Miami vibe terrace."),
        Venue(name: "Syncycle",
              category: .fitness,
              address: "Rue Lesbroussart 64, 1050 Ixelles",
              distance: 1.1,
              rating: 4.8,
              reviewCount: 187,
              websiteURL: "https://www.syncycle.be",
              instagramHandle: "syncycle",
              photoURL: "https://images.squarespace-cdn.com/content/v1/6889f6089a0d7501f7433325/501e49a7-9468-4872-944c-d4e726a31fcb/DSC05718.jpg",
              gradient: [Color(red: 0.20, green: 0.20, blue: 0.35), Color(red: 0.35, green: 0.25, blue: 0.55)],
              icon: "figure.indoor.cycle",
              tagline: "Indoor cycling studio",
              description: "An intimate indoor cycling experience in the heart of Ixelles. High-energy classes that connect body and mind to the rhythm of the music. Full-body workout, premium sound system, and great community vibes."),
        Venue(name: "Bois de la Cambre",
              category: .outdoor,
              address: "1000 Bruxelles",
              distance: 2.0,
              rating: 4.7,
              reviewCount: 3420,
              websiteURL: "https://www.visit.brussels/fr/visitors/venue-details.Bois-de-la-Cambre.17411",
              instagramHandle: "visit.brussels",
              photoURL: "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=600&q=80",
              gradient: [Color(red: 0.15, green: 0.45, blue: 0.25), Color(red: 0.08, green: 0.30, blue: 0.18)],
              icon: "leaf.fill",
              tagline: "Park · Run · Walk · Lake",
              description: "Brussels' most beautiful urban park. 124 hectares of forest, a lake, running paths, and open lawns. Perfect for a morning jog, a walk with friends, or just sitting on the grass with a book."),
        Venue(name: "Basic-Fit Ixelles",
              category: .fitness,
              address: "Chaussée d'Ixelles 29, 1050 Ixelles",
              distance: 0.8,
              rating: 4.0,
              reviewCount: 312,
              websiteURL: "https://www.basic-fit.com/fr-be/clubs/basic-fit-ixelles-chaussee-d%E2%80%99ixelles-24-7-b9b62984685e4e0abfef339ef63360ff.html",
              instagramHandle: "basicfit",
              photoURL: "https://images.unsplash.com/photo-1540497077202-7c8a3999166f?w=600&q=80",
              gradient: [Color(red: 0.90, green: 0.50, blue: 0.15), Color(red: 0.75, green: 0.30, blue: 0.10)],
              icon: "dumbbell.fill",
              tagline: "Gym · 24/7",
              description: "Open 24/7 fitness club on the Chaussée d'Ixelles. Cardio, strength, free weights, and group classes. Affordable and always accessible — no excuse to stay on your phone."),
        Venue(name: "Tour & Taxis Padel Club",
              category: .sport,
              address: "Av. du Port 86, 1000 Bruxelles",
              distance: 4.8,
              rating: 4.5,
              reviewCount: 245,
              websiteURL: "https://playtomic.com/clubs/tour-taxis-padel-club",
              instagramHandle: "tourtaxispadelclub",
              photoURL: "https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=600&q=80",
              gradient: [Color(red: 0.25, green: 0.35, blue: 0.55), Color(red: 0.15, green: 0.20, blue: 0.40)],
              icon: "sportscourt.fill",
              tagline: "Padel · 8 courts · Bar",
              description: "Brussels' biggest indoor padel facility with 8 professional courts, a bar, and a pro shop. Book a court on Playtomic, grab a friend, and play. Great way to disconnect from screens."),
        Venue(name: "Aspria Royal La Rasante",
              category: .wellness,
              address: "Rue Sombre 56, 1200 Woluwe-Saint-Lambert",
              distance: 4.5,
              rating: 4.6,
              reviewCount: 890,
              websiteURL: "https://www.aspria.com/en/brussels-royal-la-rasante",
              instagramHandle: "aspria_belgium",
              photoURL: "https://images.unsplash.com/photo-1600334089648-b0d9d3028eb2?w=600&q=80",
              gradient: [Color(red: 0.55, green: 0.40, blue: 0.60), Color(red: 0.35, green: 0.22, blue: 0.45)],
              icon: "sparkles",
              tagline: "Spa · Pool · Gym · Wellness",
              description: "A premium members club with 100 years of sporting heritage. Four hectares of gardens, seven tennis courts, two pools, state-of-the-art fitness and a world-class spa. The ultimate wellness escape."),
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
    @State private var selectedVenue: Venue? = nil
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
        .sheet(item: $selectedVenue) { venue in
            VenueDetailSheet(venue: venue, onInvite: { inviteFriend = venue })
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
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.text)
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(.clear).liquidGlass(cornerRadius: 20)
                }
            }
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
        Button(action: { selectedVenue = venue }) {
        VStack(spacing: 0) {
            // Photo
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: venue.photoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(
                                Image(systemName: venue.icon)
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(.white.opacity(0.25))
                            )
                    }
                }
                .frame(height: 160)
                .clipped()

                // Distance badge
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                    Text(String(format: "%.1f km", venue.distance))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.black.opacity(0.6))
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

                // Links
                HStack(spacing: 12) {
                    Button(action: {
                        if let url = URL(string: venue.websiteURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari").font(.system(size: 12))
                            Text("Website").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.textMuted)
                    }

                    Button(action: {
                        if let url = URL(string: "https://instagram.com/\(venue.instagramHandle)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("ig").font(.system(size: 13, weight: .heavy))
                            Text("@\(venue.instagramHandle)").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.textMuted)
                    }

                    Spacer()
                }

                // Invite a friend
                Button(action: { inviteFriend = venue }) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 13))
                        Text(L10n.t("go_with_friend"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.text)
                    .cornerRadius(12)
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .liquidGlass(cornerRadius: 18)
        }
        .buttonStyle(PlainButtonStyle())
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

// MARK: - Venue detail sheet

struct VenueDetailSheet: View {
    let venue: Venue
    var onInvite: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero image
                    ZStack(alignment: .topLeading) {
                        AsyncImage(url: URL(string: venue.photoURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .overlay(
                                        Image(systemName: venue.icon)
                                            .font(.system(size: 60, weight: .light))
                                            .foregroundColor(.white.opacity(0.2))
                                    )
                            }
                        }
                        .frame(height: 240)
                        .clipped()

                        // Close button
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.top, 56).padding(.leading, 20)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 16) {
                        // Name + rating
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(venue.name)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(Theme.text)
                                Text(venue.tagline)
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.textMuted)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.orange)
                                Text(String(format: "%.1f", venue.rating))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Theme.text)
                            }
                        }

                        // Distance + address
                        HStack(spacing: 16) {
                            HStack(spacing: 5) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textMuted)
                                Text(String(format: "%.1f km", venue.distance))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.text)
                            }
                            Text(venue.address)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textFaint)
                                .lineLimit(1)
                        }

                        // Description
                        Text(venue.description)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.textMuted)
                            .lineSpacing(5)

                        // Links
                        HStack(spacing: 16) {
                            Button(action: {
                                if let url = URL(string: venue.websiteURL) { openURL(url) }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "safari").font(.system(size: 13))
                                    Text("Website").font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(Theme.textMuted)
                            }
                            Button(action: {
                                if let url = URL(string: "https://instagram.com/\(venue.instagramHandle)") { openURL(url) }
                            }) {
                                HStack(spacing: 5) {
                                    Text("ig").font(.system(size: 14, weight: .heavy))
                                    Text("@\(venue.instagramHandle)").font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(Theme.textMuted)
                            }
                        }

                        // CTA
                        Button(action: { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onInvite() } }) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 14))
                                Text(L10n.t("go_with_friend"))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(Theme.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.text)
                            .cornerRadius(14)
                        }
                        .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
        }
    }
}
