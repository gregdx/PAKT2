import SwiftUI
import CoreLocation

// MARK: - Venue model

struct Venue: Identifiable {
    let id = UUID()
    let name: String
    let category: VenueCategory
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double
    let reviewCount: Int
    let websiteURL: String
    let instagramHandle: String
    let photoURL: String // remote image
    let gradient: [Color] // fallback gradient
    let icon: String
    let tagline: String
    let description: String

    /// Compute distance in km from the user's current location
    func distanceFrom(_ userLocation: CLLocation) -> Double {
        let venueLocation = CLLocation(latitude: latitude, longitude: longitude)
        return userLocation.distance(from: venueLocation) / 1000.0
    }
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

    /// Slug sent to /v1/spots?categories=… — must match the backend's category
    /// values (lowercase, ASCII, no accents).
    var backendSlug: String {
        switch self {
        case .fitness:  return "fitness"
        case .cafe:     return "cafe"
        case .outdoor:  return "outdoor"
        case .wellness: return "wellness"
        case .sport:    return "sport"
        }
    }
}

// MARK: - Sample venues

extension Venue {
    static let all: [Venue] = [
        Venue(name: "Le Flore",
              category: .cafe,
              address: "Av. de Flore 3, 1000 Bruxelles",
              latitude: 50.8120, longitude: 4.3740,
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
              latitude: 50.8260, longitude: 4.3740,
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
              latitude: 50.8100, longitude: 4.3730,
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
              latitude: 50.8330, longitude: 4.3640,
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
              latitude: 50.8660, longitude: 4.3490,
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
              latitude: 50.8400, longitude: 4.4210,
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

enum DiscoverTab: CaseIterable {
    case events, spots, free

    var label: String {
        switch self {
        case .spots:  return L10n.t("spots")
        case .events: return L10n.t("events")
        case .free:   return L10n.t("free_activities")
        }
    }

    var icon: String {
        switch self {
        case .spots:  return "mappin.circle"
        case .events: return "ticket"
        case .free:   return "figure.walk"
        }
    }
}

// MARK: - NearYouView

struct NearYouView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fm = FriendManager.shared
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var stManager = ScreenTimeManager.shared
    @StateObject private var locationManager = AppLocationManager()

    @State private var discoverTab: DiscoverTab = .events
    @State private var showCreateEvent = false
    @State private var selectedCategory: VenueCategory? = nil
    /// Remote-first "Free activities" catalogue (replaces Activity.suggestions).
    @StateObject private var activitiesStore = ActivitiesRemoteStore.shared
    @State private var showFreeFilters: Bool = false
    @State private var freeSearchTask: Task<Void, Never>? = nil
    @State private var radiusKm: Double = 15.0
    @State private var showRadiusPicker = false
    @State private var inviteFriend: Venue? = nil
    @State private var selectedVenue: Venue? = nil
    @State private var appeared = false

    // Remote spots (replaces hardcoded Venue.all + Foursquare fallback)
    @StateObject private var spotsStore = SpotsRemoteStore.shared
    @StateObject private var eventsStore = EventsRemoteStore.shared
    @State private var spotsQuery: String = ""
    @State private var spotsSearchVisible: Bool = false
    @State private var spotsSearchTask: Task<Void, Never>? = nil
    @State private var selectedSpot: APIClient.APISpot? = nil

    // Brussels events
    @State private var brusselsEvents: [BrusselsEvent] = []
    @State private var brusselsLoading = false
    @State private var brusselsLoaded = false

    // Resident Advisor
    @State private var raEvents: [RAEvent] = []
    @State private var raLoading = false
    @State private var raLoaded = false
    @State private var raError: String? = nil
    @State private var selectedRAEvent: RAEvent? = nil

    /// Active city for the spots feed. Falls back to "city_brussels" so the
    /// feature works before the user explicitly picks a city.
    private var activeCityId: String {
        eventsStore.selectedCityId ?? "city_brussels"
    }

    /// Remote spots filtered by radius and category on the client so the slider
    /// still works without an extra request per change.
    private var filteredRemoteSpots: [APIClient.APISpot] {
        let cat = selectedCategory?.backendSlug
        let base = spotsStore.spots.filter { spot in
            cat == nil || spot.category.lowercased() == cat
        }
        guard let userLocation = locationManager.location else {
            return base
        }
        return base
            .filter { SpotsRemoteStore.distanceKm(spot: $0, from: userLocation) <= radiusKm }
            .sorted {
                SpotsRemoteStore.distanceKm(spot: $0, from: userLocation)
                    < SpotsRemoteStore.distanceKm(spot: $1, from: userLocation)
            }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                EventsFeedView()
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            locationManager.requestPermission()
            locationManager.startUpdating()
        }
        .onChange(of: selectedCategory) { _, _ in
            Task { await reloadSpots() }
        }
        .onChange(of: spotsQuery) { _, _ in
            spotsSearchTask?.cancel()
            spotsSearchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await reloadSpots()
            }
        }
        .onChange(of: locationManager.location) { _, newLoc in
            guard newLoc != nil else { return }
            if discoverTab == .events && !raLoaded && !raLoading {
                loadRAEvents()
            }
            if discoverTab == .events && !brusselsLoaded && !brusselsLoading {
                loadBrusselsEvents()
            }
        }
        .sheet(item: $selectedSpot) { spot in
            SpotDetailSheet(spot: spot, userLocation: locationManager.location)
        }
        .sheet(item: $inviteFriend) { venue in
            InviteFriendSheet(venue: venue, friends: fm.friends)
                .environmentObject(appState)
        }
        .sheet(item: $selectedVenue) { venue in
            VenueDetailSheet(venue: venue, userLocation: locationManager.location, onInvite: { inviteFriend = venue })
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventSheet().environmentObject(appState)
        }
        .sheet(item: $selectedRAEvent) { event in
            RAEventDetailSheet(event: event)
        }
    }

    // MARK: - Load Brussels events

    private func loadBrusselsEvents() {
        guard let loc = locationManager.location else { return }
        brusselsLoading = true
        Task {
            do {
                let events = try await BrusselsEventsService.shared.fetchEvents(
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    radiusKm: Int(radiusKm)
                )
                await MainActor.run {
                    brusselsEvents = events
                    brusselsLoading = false
                    brusselsLoaded = true
                }
            } catch {
                await MainActor.run {
                    brusselsLoading = false
                    brusselsLoaded = true
                }
                Log.e("[Brussels] Error: \(error)")
            }
        }
    }

    // MARK: - Load RA events

    private func loadRAEvents() {
        raLoading = true
        raError = nil
        Task {
            do {
                let events = try await ResidentAdvisorService.shared.fetchEvents()
                await MainActor.run {
                    raEvents = events
                    raLoading = false
                    raLoaded = true
                }
            } catch {
                await MainActor.run {
                    raError = error.localizedDescription
                    raLoading = false
                    raLoaded = true
                }
            }
        }
    }

    // MARK: - Load Spots (remote)

    /// Fetch the spots feed from /v1/spots. Category filtering is applied
    /// server-side so the payload stays small when a chip is active.
    private func reloadSpots(forceRefresh: Bool = false) async {
        let cats = selectedCategory.map { [$0.backendSlug] } ?? []
        await spotsStore.loadSpots(
            cityId: activeCityId,
            categories: cats,
            query: spotsQuery.trimmingCharacters(in: .whitespaces),
            forceRefresh: forceRefresh
        )
    }

    // MARK: - RA Event helpers

    private func paktEventForRA(_ event: RAEvent) -> PaktEvent? {
        eventManager.events.first { $0.id == "ra_\(event.id)" }
    }

    private func toggleRAGoing(_ event: RAEvent) {
        let paktId = eventManager.ensureRAEvent(raEvent: event)
        eventManager.toggleGoing(eventId: paktId, userId: appState.currentUID)
    }

    private func toggleRAInterested(_ event: RAEvent) {
        let paktId = eventManager.ensureRAEvent(raEvent: event)
        eventManager.toggleInterested(eventId: paktId, userId: appState.currentUID)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("near_you_title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            if stManager.profileToday > 0 {
                Text("\(formatTime(stManager.profileToday)) \(L10n.t("on_phone_today"))")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
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
            .foregroundColor(isSelected ? .white : Theme.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(isSelected ? Theme.text : Theme.bgCard)
            )
        }
    }

    // MARK: - Discover tabs (Spots / Events / Free)

    private var discoverTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoverTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            discoverTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: discoverTab == tab ? .semibold : .regular))
                            Text(tab.label)
                                .font(.system(size: 15, weight: discoverTab == tab ? .semibold : .regular))
                        }
                        .foregroundColor(discoverTab == tab ? .white : Theme.text)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule().fill(discoverTab == tab ? Theme.text : Theme.bgCard)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 16)
    }
    

    // MARK: - PAKT Events List (local events)

    private var paktEventsList: some View {
        let upcoming = eventManager.upcomingEvents()
        let myUid = appState.currentUID
        return VStack(spacing: 16) {
            // Create event button
            Button(action: { showCreateEvent = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    Text(L10n.t("create_event"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .liquidGlass(cornerRadius: 16)
            }
            .padding(.horizontal, 24)

            if !upcoming.isEmpty {
                ForEach(upcoming) { event in
                    PaktEventCard(event: event, myUid: myUid)
                        .environmentObject(appState)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Brussels Events List

    private var brusselsEventsList: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("brussels_agenda"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textFaint)
                        .tracking(1.2)
                    Text(L10n.t("powered_by_brussels"))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                if !brusselsEvents.isEmpty {
                    Button(action: { loadBrusselsEvents() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if brusselsLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.textMuted)
                    Text(L10n.t("loading"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 20)
            } else {
                ForEach(brusselsEvents) { event in
                    brusselsEventCard(event)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Brussels Event Card

    private func brusselsEventCard(_ event: BrusselsEvent) -> some View {
        VStack(spacing: 0) {
            // Image or fallback
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    Color(red: 0.10, green: 0.10, blue: 0.10)

                    if let imageStr = event.imageURL, let url = URL(string: imageStr) {
                        CachedAsyncImage(url: url)
                            .scaledToFill()
                    } else {
                        Text(event.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(height: 160)
                .clipped()

                // Category badge + distance
                HStack(spacing: 8) {
                    Text(event.category.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)

                    if event.distance > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f km", event.distance))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 8) {
                // Name
                Text(event.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Description
                if let desc = event.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(3)
                }

                // Address (tappable -> Apple Maps)
                if !event.address.isEmpty {
                    Button(action: {
                        if let url = event.mapsURL {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                            Text(event.address)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.blue)
                                .lineLimit(1)
                        }
                    }
                }

                // Website link
                if let websiteStr = event.website, let url = URL(string: websiteStr) {
                    Button(action: { UIApplication.shared.open(url) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari").font(.system(size: 12))
                            Text(L10n.t("website")).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .padding(14)
        }
        .liquidGlass(cornerRadius: 18)
    }

    // MARK: - Resident Advisor Events List

    private var raEventsList: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("nearby_events").uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textFaint)
                        .tracking(1.2)
                    Text("Powered by Resident Advisor")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                }
                Spacer()
                if !raEvents.isEmpty {
                    Button(action: { loadRAEvents() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if raLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.textMuted)
                    Text(L10n.t("loading"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 20)
            } else if let error = raError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textFaint)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                    Button(action: { loadRAEvents() }) {
                        Text(L10n.t("retry"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .liquidGlass(cornerRadius: 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            } else {
                ForEach(raEvents) { event in
                    raEventCard(event)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - RA Event Card

    private func raEventCard(_ event: RAEvent) -> some View {
        Button(action: { selectedRAEvent = event }) {
            VStack(spacing: 0) {
                // Image
                ZStack(alignment: .bottomLeading) {
                    if let imageStr = event.flyerFront, let url = URL(string: imageStr) {
                        CachedAsyncImage(url: url)
                            .scaledToFill()
                            .frame(height: 160)
                            .clipped()
                    } else {
                        Color(red: 0.10, green: 0.10, blue: 0.10)
                            .frame(height: 160)
                            .overlay(
                                VStack(spacing: 6) {
                                    if let venueName = event.venueName {
                                        Text(venueName)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    Text(event.formattedDate)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            )
                    }

                    // Venue badge (only on images)
                    if event.flyerFront != nil, let venueName = event.venueName {
                        Text(venueName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .padding(12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Info
                VStack(alignment: .leading, spacing: 8) {
                    // Date
                    Text(event.formattedDate)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.orange)

                    // Title
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Venue + City
                    if let venueName = event.venueName {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                            Text(venueName)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                            if let city = event.venueCity {
                                Text("- \(city)")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textFaint)
                            }
                        }
                    }

                    // Artists
                    if let artists = event.artistNames {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textFaint)
                            Text(artists)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    // Friends going/interested
                    let pakt = paktEventForRA(event)
                    if let p = pakt {
                        let goingFriends = eventManager.friendNames(for: p.goingIds, friendManager: fm)
                        let interestedFriends = eventManager.friendNames(for: p.interestedIds, friendManager: fm)
                        if !goingFriends.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(Theme.green)
                                Text(goingFriends.joined(separator: ", "))
                                    .font(.system(size: 12)).foregroundColor(Theme.green).lineLimit(1)
                            }
                        }
                        if !interestedFriends.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(Theme.orange)
                                Text(interestedFriends.joined(separator: ", "))
                                    .font(.system(size: 12)).foregroundColor(Theme.orange).lineLimit(1)
                            }
                        }
                    }

                    // Going / Interested buttons
                    HStack(spacing: 10) {
                        let isGoing = pakt?.goingIds.contains(appState.currentUID) ?? false
                        let isInterested = pakt?.interestedIds.contains(appState.currentUID) ?? false

                        Button(action: { toggleRAGoing(event) }) {
                            HStack(spacing: 5) {
                                Image(systemName: isGoing ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.system(size: 13))
                                Text(L10n.t("going"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(isGoing ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isGoing ? Theme.green : Color.clear)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isGoing ? Color.clear : Theme.textFaint.opacity(0.3), lineWidth: 1)
                            )
                        }

                        Button(action: { toggleRAInterested(event) }) {
                            HStack(spacing: 5) {
                                Image(systemName: isInterested ? "star.fill" : "star")
                                    .font(.system(size: 13))
                                Text(L10n.t("interested"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(isInterested ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isInterested ? Theme.orange : Color.clear)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isInterested ? Color.clear : Theme.textFaint.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(14)
            }
            .liquidGlass(cornerRadius: 18)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Free activities (remote-first with offline fallback)

    /// Search bar + "Filters" button in a single row above the category pills.
    private var freeSearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                TextField(L10n.t("search_activities"),
                          text: Binding(
                            get: { activitiesStore.filters.searchText },
                            set: { newVal in
                                activitiesStore.filters.searchText = newVal
                            }))
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .submitLabel(.search)
                if !activitiesStore.filters.searchText.isEmpty {
                    Button {
                        activitiesStore.filters.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 14)

            Button {
                showFreeFilters = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("advanced_filters"))
                        .font(.system(size: 13, weight: .semibold))
                    if activitiesStore.filters.activeCount > 0 {
                        Text("\(activitiesStore.filters.activeCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.blue))
                    }
                }
                .foregroundColor(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .liquidGlass(cornerRadius: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .onChange(of: activitiesStore.filters.searchText) { _, _ in
            freeSearchTask?.cancel()
            freeSearchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await activitiesStore.load(cityId: activeCityId)
            }
        }
        .onChange(of: activitiesStore.filters.categories) { _, _ in
            Task { await activitiesStore.load(cityId: activeCityId) }
        }
        .onChange(of: activitiesStore.filters.featuredOnly) { _, _ in
            Task { await activitiesStore.load(cityId: activeCityId) }
        }
        .task {
            // Initial fetch. Duration filter is client-side so it doesn't trigger loads.
            await activitiesStore.load(cityId: activeCityId)
        }
        .sheet(isPresented: $showFreeFilters) {
            AdvancedFiltersSheet(
                selection: $activitiesStore.filters,
                categories: AdvancedFiltersSheet.FilterCategoryOption.freeActivityCategories,
                showDurationSection: true,
                showFeaturedToggle: true
            )
            .presentationDetents([.medium, .large])
        }
    }

    /// Horizontal category quick-pick row. Writes into the shared selection
    /// so it stays in sync with the advanced filters sheet. "All" clears the
    /// multi-select back to empty.
    private var freeCategoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(label: L10n.t("all"),
                     icon: nil,
                     isSelected: activitiesStore.filters.categories.isEmpty) {
                    activitiesStore.filters.categories.removeAll()
                }
                ForEach(ActCategory.allCases, id: \.self) { cat in
                    let isOn = activitiesStore.filters.categories.contains(cat.rawValue)
                    pill(label: cat.label, icon: nil, isSelected: isOn) {
                        if isOn {
                            activitiesStore.filters.categories.remove(cat.rawValue)
                        } else {
                            activitiesStore.filters.categories.insert(cat.rawValue)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var freeActivitiesList: some View {
        if activitiesStore.didLoadRemote {
            let items = activitiesStore.filteredActivities
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("no_activities_found"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { activity in
                        remoteActivityCard(activity)
                    }
                }
                .padding(.horizontal, 24)
            }
        } else if activitiesStore.isLoading {
            ProgressView()
                .tint(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            // Offline fallback: hardcoded Activity.suggestions, filtered by the
            // selected quick-pick categories so the UI still feels responsive.
            let selectedCats = activitiesStore.filters.categories
            let base: [Activity] = selectedCats.isEmpty
                ? Activity.suggestions
                : Activity.suggestions.filter { selectedCats.contains($0.category.rawValue) }

            VStack(spacing: 12) {
                ForEach(base) { activity in
                    freeActivityCard(activity)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// Card for a remote APIActivity. Mirrors the layout of the legacy offline
    /// card so the visual transition is seamless.
    private func remoteActivityCard(_ activity: APIClient.APIActivity) -> some View {
        let cat = ActCategory(rawValue: activity.category) ?? .chill
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(cat.color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: cat.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(cat.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activity.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                    if activity.isFeatured {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                }
                Text(activity.description)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(2)
                if let m = activity.durationMinutes {
                    Text("\(m) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textFaint)
                }
            }
            Spacer()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 16)
    }

    /// Offline-fallback card for the legacy `Activity` struct.
    private func freeActivityCard(_ activity: Activity) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(activity.category.color.opacity(0.1))
                    .frame(width: 52, height: 52)
                Text(activity.emoji)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(activity.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Search (spots)

    private var spotsSearchBarToggle: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    spotsSearchVisible.toggle()
                    if !spotsSearchVisible { spotsQuery = "" }
                }
            } label: {
                Image(systemName: spotsSearchVisible ? "xmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 36, height: 36)
                    .liquidGlass(cornerRadius: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var spotsSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(Theme.textFaint)
            TextField("Search spots...", text: $spotsQuery)
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Venues list (remote /v1/spots)

    private var venuesList: some View {
        VStack(spacing: 14) {
            if spotsStore.isLoading && spotsStore.spots.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.textMuted)
                    Text(L10n.t("loading"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.top, 40)
            } else if filteredRemoteSpots.isEmpty {
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
                ForEach(filteredRemoteSpots) { spot in
                    spotCard(spot)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Remote spot card (mirrors Events card polish)

    private func spotCard(_ spot: APIClient.APISpot) -> some View {
        Button(action: { selectedSpot = spot }) {
            VStack(spacing: 0) {
                // Photo
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.22, blue: 0.30), Color(red: 0.10, green: 0.12, blue: 0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .overlay(
                            Image(systemName: iconForCategory(spot.category))
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(.white.opacity(0.25))
                        )
                        if !spot.imageUrl.isEmpty, let url = URL(string: spot.imageUrl) {
                            CachedAsyncImage(url: url).scaledToFill()
                        }
                    }
                    .frame(height: 160)
                    .clipped()

                    HStack(spacing: 8) {
                        Text(spot.category.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)

                        if let userLocation = locationManager.location {
                            let km = SpotsRemoteStore.distanceKm(spot: spot, from: userLocation)
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill").font(.system(size: 10))
                                Text(String(format: "%.1f km", km))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spot.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Theme.text)
                                .multilineTextAlignment(.leading)
                            if !spot.tagline.isEmpty {
                                Text(spot.tagline)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textMuted)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        if let rating = spot.rating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.orange)
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.text)
                            }
                        }
                    }

                    if !spot.address.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                            Text(spot.address)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.blue)
                                .lineLimit(1)
                        }
                    }

                    // Website + Instagram
                    HStack(spacing: 14) {
                        if !spot.websiteUrl.isEmpty, let url = URL(string: spot.websiteUrl) {
                            Button(action: { UIApplication.shared.open(url) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "safari").font(.system(size: 12))
                                    Text(L10n.t("website")).font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(Theme.textMuted)
                            }
                        }
                        if !spot.instagram.isEmpty,
                           let url = URL(string: "https://instagram.com/\(spot.instagram)") {
                            Button(action: { UIApplication.shared.open(url) }) {
                                HStack(spacing: 4) {
                                    Text(L10n.t("instagram_short")).font(.system(size: 13, weight: .heavy))
                                    Text("@\(spot.instagram)").font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(Theme.textMuted)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(14)
            }
            .liquidGlass(cornerRadius: 18)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForCategory(_ raw: String) -> String {
        switch raw.lowercased() {
        case "fitness":  return "figure.run"
        case "cafe":     return "cup.and.saucer.fill"
        case "outdoor":  return "leaf.fill"
        case "wellness": return "sparkles"
        case "sport":    return "sportscourt.fill"
        default:         return "mappin.circle.fill"
        }
    }

    // MARK: - Foursquare Spot Card

    private func fsqSpotCard(_ spot: DiscoverSpot) -> some View {
        VStack(spacing: 0) {
            // Photo
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    // Fallback gradient
                    LinearGradient(
                        colors: [Color(red: 0.25, green: 0.30, blue: 0.45), Color(red: 0.15, green: 0.18, blue: 0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: spot.venueCategory?.icon ?? "mappin.circle.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.white.opacity(0.25))
                    )

                    // Real photo from Foursquare
                    if let photoURL = spot.photoURL, let url = URL(string: photoURL) {
                        CachedAsyncImage(url: url)
                            .scaledToFill()
                    }
                }
                .frame(height: 160)
                .clipped()

                // Distance badge
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                    Text(String(format: "%.1f km", spot.distance))
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
                        Text(spot.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text(spot.category)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    // Rating (if available)
                    if let rating = spot.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.orange)
                            Text(String(format: "%.1f", rating / 2.0))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.text)
                        }
                    }
                }

                // Address (tappable -> Apple Maps)
                if !spot.address.isEmpty {
                    Button(action: {
                        let encoded = spot.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textFaint)
                            Text(spot.address)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.blue)
                                .lineLimit(1)
                        }
                    }
                }

                // Website link
                if let website = spot.website, let url = URL(string: website) {
                    Button(action: { UIApplication.shared.open(url) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari").font(.system(size: 12))
                            Text(L10n.t("website")).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.textMuted)
                    }
                }
            }
            .padding(14)
        }
        .liquidGlass(cornerRadius: 18)
    }

    // MARK: - Venue card

    private func venueCard(_ venue: Venue) -> some View {
        Button(action: { selectedVenue = venue }) {
        VStack(spacing: 0) {
            // Photo
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: venue.icon).font(.system(size: 40, weight: .light)).foregroundColor(.white.opacity(0.25)))
                    CachedAsyncImage(url: URL(string: venue.photoURL)).scaledToFill()
                }
                .frame(height: 160)
                .clipped()

                // Distance badge
                if let userLocation = locationManager.location {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f km", venue.distanceFrom(userLocation)))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .padding(12)
                }
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

                // Address (tappable → Maps)
                Button(action: {
                    let encoded = venue.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textFaint)
                        Text(venue.address)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.blue)
                            .lineLimit(1)
                    }
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
                            Text(L10n.t("website")).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.textMuted)
                    }

                    Button(action: {
                        if let url = URL(string: "https://instagram.com/\(venue.instagramHandle)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(L10n.t("instagram_short")).font(.system(size: 13, weight: .heavy))
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
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Venue detail sheet

struct VenueDetailSheet: View {
    let venue: Venue
    var userLocation: CLLocation?
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
                        ZStack {
                            LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .overlay(Image(systemName: venue.icon).font(.system(size: 60, weight: .light)).foregroundColor(.white.opacity(0.2)))
                            CachedAsyncImage(url: URL(string: venue.photoURL)).scaledToFill()
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

                        // Distance + address (tappable → Maps)
                        Button(action: {
                            let encoded = venue.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") { openURL(url) }
                        }) {
                            HStack(spacing: 16) {
                                HStack(spacing: 5) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.textMuted)
                                    Text(userLocation.map { String(format: "%.1f km", venue.distanceFrom($0)) } ?? "")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                }
                                Text(venue.address)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.blue)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "map").font(.system(size: 13)).foregroundColor(Theme.blue)
                            }
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
                                    Text(L10n.t("website")).font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(Theme.textMuted)
                            }
                            Button(action: {
                                if let url = URL(string: "https://instagram.com/\(venue.instagramHandle)") { openURL(url) }
                            }) {
                                HStack(spacing: 5) {
                                    Text(L10n.t("instagram_short")).font(.system(size: 14, weight: .heavy))
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

// MARK: - Event Detail Sheet

struct RAEventDetailSheet: View {
    let event: RAEvent
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @EnvironmentObject var appState: AppState
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var fm = FriendManager.shared
    @State private var showInvite = false
    @State private var calendarAdded = false

    private var paktId: String { "ra_\(event.id)" }
    private var paktEvent: PaktEvent? { eventManager.events.first { $0.id == paktId } }
    private var isGoing: Bool { paktEvent?.goingIds.contains(appState.currentUID) ?? false }
    private var isInterested: Bool { paktEvent?.interestedIds.contains(appState.currentUID) ?? false }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero image
                    ZStack(alignment: .topLeading) {
                        if let imageStr = event.flyerFront, let url = URL(string: imageStr) {
                            CachedAsyncImage(url: url)
                                .scaledToFill()
                                .frame(height: 280)
                                .clipped()
                        } else {
                            Color(red: 0.10, green: 0.10, blue: 0.10)
                                .frame(height: 280)
                                .overlay(
                                    VStack(spacing: 8) {
                                        if let venueName = event.venueName {
                                            Text(venueName)
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                        Text(event.formattedDate)
                                            .font(.system(size: 15))
                                            .foregroundColor(.white.opacity(0.25))
                                    }
                                )
                        }

                        // Close button
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.top, 56)
                        .padding(.leading, 20)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        Text(event.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Theme.text)

                        // Date & time
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Theme.text)
                            Text(event.formattedDate)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.text)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                        )
                        .liquidGlass(cornerRadius: 12, style: .ultraThin)

                        // Venue
                        if let venue = event.venue {
                            Button(action: {
                                if let addr = venue.address, !addr.isEmpty,
                                   let encoded = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                   let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                                    openURL(url)
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.t("venue_label"))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Theme.textFaint)
                                        .tracking(1.0)

                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(Theme.text)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(venue.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(Theme.text)
                                            if let address = venue.address {
                                                Text(address)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(Theme.blue)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.5))
                                )
                                .liquidGlass(cornerRadius: 14, style: .ultraThin)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Artists / Lineup
                        if let artists = event.artists, !artists.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LINEUP")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Theme.textFaint)
                                    .tracking(1.0)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                                    ForEach(artists, id: \.name) { artist in
                                        Text(artist.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Theme.text)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .liquidGlass(cornerRadius: 10)
                                    }
                                }
                            }
                        }

                        // Going / Interested
                        HStack(spacing: 12) {
                            Button(action: {
                                let _ = eventManager.ensureRAEvent(raEvent: event)
                                eventManager.toggleGoing(eventId: paktId, userId: appState.currentUID)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: isGoing ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.system(size: 15))
                                    Text(L10n.t("going"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(isGoing ? .white : Theme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isGoing ? Theme.green : Color.clear)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isGoing ? Color.clear : Theme.textFaint.opacity(0.3), lineWidth: 1)
                                )
                            }

                            Button(action: {
                                let _ = eventManager.ensureRAEvent(raEvent: event)
                                eventManager.toggleInterested(eventId: paktId, userId: appState.currentUID)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: isInterested ? "star.fill" : "star")
                                        .font(.system(size: 15))
                                    Text(L10n.t("interested"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(isInterested ? .white : Theme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isInterested ? Theme.orange : Color.clear)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isInterested ? Color.clear : Theme.textFaint.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }

                        // Friends going / interested
                        if let p = paktEvent {
                            let goingFriends = eventManager.friendNames(for: p.goingIds.filter { $0 != appState.currentUID }, friendManager: fm)
                            let interestedFriends = eventManager.friendNames(for: p.interestedIds.filter { $0 != appState.currentUID }, friendManager: fm)

                            if !goingFriends.isEmpty || !interestedFriends.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    if !goingFriends.isEmpty {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(Theme.green)
                                            Text(goingFriends.joined(separator: ", "))
                                                .font(.system(size: 14)).foregroundColor(Theme.text)
                                        }
                                    }
                                    if !interestedFriends.isEmpty {
                                        HStack(spacing: 6) {
                                            Image(systemName: "star.fill").font(.system(size: 13)).foregroundColor(Theme.orange)
                                            Text(interestedFriends.joined(separator: ", "))
                                                .font(.system(size: 14)).foregroundColor(Theme.text)
                                        }
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlass(cornerRadius: 12)
                            }
                        }

                        // Add to Calendar
                        Button(action: {
                            let _ = eventManager.ensureRAEvent(raEvent: event)
                            if let p = eventManager.events.first(where: { $0.id == paktId }) {
                                EventManager.addToCalendar(event: p) { ok in calendarAdded = ok }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: calendarAdded ? "checkmark.circle.fill" : "calendar.badge.plus")
                                    .font(.system(size: 15))
                                Text(calendarAdded ? L10n.t("added_to_calendar") : L10n.t("add_to_calendar"))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(calendarAdded ? Theme.green : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .liquidGlass(cornerRadius: 12)
                        }

                        // Share event (always visible)
                        Button(action: { showInvite = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15))
                                Text(L10n.t("share_event"))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .liquidGlass(cornerRadius: 12)
                        }

                        // Open on RA
                        Button(action: {
                            if let url = URL(string: event.eventURL) {
                                openURL(url)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                    .font(.system(size: 15))
                                Text(L10n.t("see_event"))
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                            .cornerRadius(14)
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            RAInviteSheet(event: event)
                .environmentObject(appState)
        }
    }
}

// MARK: - Invite friends to RA event

struct RAInviteSheet: View {
    let event: RAEvent
    @EnvironmentObject var appState: AppState
    @ObservedObject private var fm = FriendManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var sentIds: Set<String> = []
    @State private var sendingIds: Set<String> = []
    @State private var sentGroupIds: Set<String> = []
    @State private var sendingGroupIds: Set<String> = []
    @State private var personalMessage: String = ""

    private var eventMessage: String {
        var msg = ""
        let trimmed = personalMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { msg += trimmed + "\n" }
        let venue = event.venueName ?? ""
        msg += "\(event.title) — \(event.formattedDate)"
        if !venue.isEmpty { msg += " @ \(venue)" }
        if let artists = event.artistNames { msg += "\n\(artists)" }
        msg += "\n\(event.eventURL)"
        return msg
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t("share_event"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 30, height: 30)
                            .background(Theme.textFaint.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(24)

                VStack(spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(event.formattedDate)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.orange)
                }
                .padding(.bottom, 12)

                // Personal message field
                HStack(spacing: 8) {
                    TextField(L10n.t("add_message"), text: $personalMessage)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .liquidGlass(cornerRadius: 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Groups
                        if !appState.groups.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.t("groups").uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Theme.textFaint)
                                    .tracking(1.2)
                                    .padding(.horizontal, 24)

                                ForEach(appState.groups) { group in
                                    let gid = group.id.uuidString
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                            .frame(width: 36, height: 36)
                                            .background(Theme.textFaint.opacity(0.3))
                                            .clipShape(Circle())
                                        Text(group.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Theme.text)
                                        Spacer()
                                        if sentGroupIds.contains(gid) {
                                            sentBadge
                                        } else if sendingGroupIds.contains(gid) {
                                            ProgressView().scaleEffect(0.8).tint(Theme.textMuted)
                                        } else {
                                            Button(action: { sendToGroup(group) }) { sendBtn }
                                        }
                                    }
                                    .padding(.horizontal, 24).padding(.vertical, 6)
                                }
                            }
                        }

                        // Friends
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.t("friends").uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textFaint)
                                .tracking(1.2)
                                .padding(.horizontal, 24)

                            ForEach(fm.friends, id: \.id) { friend in
                                HStack(spacing: 12) {
                                    Text(friend.firstName.prefix(1).uppercased())
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Theme.textFaint.opacity(0.3))
                                        .clipShape(Circle())
                                    Text(friend.firstName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Theme.text)
                                    Spacer()
                                    if sentIds.contains(friend.id) {
                                        sentBadge
                                    } else if sendingIds.contains(friend.id) {
                                        ProgressView().scaleEffect(0.8).tint(Theme.textMuted)
                                    } else {
                                        Button(action: { sendToFriend(friend) }) { sendBtn }
                                    }
                                }
                                .padding(.horizontal, 24).padding(.vertical, 6)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var sendBtn: some View {
        Text(L10n.t("send"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Theme.text)
            .padding(.vertical, 7).padding(.horizontal, 16)
            .liquidGlass(cornerRadius: 10)
    }

    private var sentBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
            Text(L10n.t("sent")).font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(Theme.green)
    }

    private func sendToFriend(_ friend: AppUser) {
        sendingIds.insert(friend.id)
        Task {
            do {
                _ = try await APIClient.shared.sendChatMessage(text: eventMessage, toId: friend.id)
                await MainActor.run { sendingIds.remove(friend.id); _ = sentIds.insert(friend.id) }
            } catch {
                await MainActor.run { _ = sendingIds.remove(friend.id) }
                Log.e("[RAShare] Send failed: \(error)")
            }
        }
    }

    private func sendToGroup(_ group: Group) {
        let gid = group.id.uuidString
        sendingGroupIds.insert(gid)
        Task {
            do {
                _ = try await APIClient.shared.sendGroupMessage(groupID: gid, text: eventMessage)
                await MainActor.run { sendingGroupIds.remove(gid); _ = sentGroupIds.insert(gid) }
            } catch {
                await MainActor.run { _ = sendingGroupIds.remove(gid) }
                Log.e("[RAShare] Group send failed: \(error)")
            }
        }
    }
}

// MARK: - Spot detail sheet (remote APISpot)

struct SpotDetailSheet: View {
    let spot: APIClient.APISpot
    var userLocation: CLLocation?
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero
                    ZStack(alignment: .topLeading) {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 0.20, green: 0.22, blue: 0.30), Color(red: 0.10, green: 0.12, blue: 0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            if !spot.imageUrl.isEmpty, let url = URL(string: spot.imageUrl) {
                                CachedAsyncImage(url: url).scaledToFill()
                            }
                        }
                        .frame(height: 240)
                        .clipped()

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

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(spot.name)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(Theme.text)
                                if !spot.tagline.isEmpty {
                                    Text(spot.tagline)
                                        .font(.system(size: 15))
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                            Spacer()
                            if let rating = spot.rating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.orange)
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(Theme.text)
                                }
                            }
                        }

                        if !spot.address.isEmpty {
                            Button(action: {
                                let encoded = spot.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") { openURL(url) }
                            }) {
                                HStack(spacing: 16) {
                                    if let userLocation = userLocation {
                                        HStack(spacing: 5) {
                                            Image(systemName: "location.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(Theme.textMuted)
                                            Text(String(format: "%.1f km", SpotsRemoteStore.distanceKm(spot: spot, from: userLocation)))
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(Theme.text)
                                        }
                                    }
                                    Text(spot.address)
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.blue)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "map").font(.system(size: 13)).foregroundColor(Theme.blue)
                                }
                            }
                        }

                        if !spot.description.isEmpty {
                            Text(spot.description)
                                .font(.system(size: 15))
                                .foregroundColor(Theme.textMuted)
                                .lineSpacing(5)
                        }

                        HStack(spacing: 16) {
                            if !spot.websiteUrl.isEmpty, let url = URL(string: spot.websiteUrl) {
                                Button(action: { openURL(url) }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "safari").font(.system(size: 13))
                                        Text(L10n.t("website")).font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(Theme.textMuted)
                                }
                            }
                            if !spot.instagram.isEmpty,
                               let url = URL(string: "https://instagram.com/\(spot.instagram)") {
                                Button(action: { openURL(url) }) {
                                    HStack(spacing: 5) {
                                        Text(L10n.t("instagram_short")).font(.system(size: 14, weight: .heavy))
                                        Text("@\(spot.instagram)").font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(Theme.textMuted)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
    }
}
