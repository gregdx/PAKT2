import SwiftUI
import CoreLocation
import MapKit

/// D-hybrid events feed: header (city picker + search + map toggle) →
/// sticky filter chips → hero horizontal "Ce weekend" scroll → sections
/// ("Tes amis y vont" / "Cette semaine") → event cards (XL and M).
///
/// Drops into NearYouView's events sub-tab as a single self-contained view.
/// All data comes from EventsRemoteStore which talks to /v1/events + /v1/cities.
struct EventsFeedView: View {
    @StateObject private var store = EventsRemoteStore.shared
    @StateObject private var locationManager = AppLocationManager()

    // Feed slices
    @State private var heroEvents: [APIClient.APIEventListRow] = []
    @State private var friendsEvents: [APIClient.APIEventListRow] = []
    @State private var weekEvents: [APIClient.APIEventListRow] = []
    @State private var myEvents: [APIClient.APIUserEvent] = []

    // Loading flags
    @State private var loading = false
    @State private var loaded = false
    @State private var lastError: String? = nil
    /// Debounce task for coalescing filter/city/mode changes into one reload.
    @State private var reloadDebounce: Task<Void, Never>? = nil

    // UI state
    @State private var viewMode: ViewMode = .events
    @State private var activeFilter: FilterChip = .forYou
    @State private var searchQuery = ""
    @State private var showCityPicker = false
    @State private var showSearchBar = false
    @State private var showCreateSheet = false
    @State private var selectedEvent: APIClient.APIEventListRow? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    @State private var showFullMap: Bool = false
    @StateObject private var spotsStore = SpotsRemoteStore.shared
    @StateObject private var activitiesStore = ActivitiesRemoteStore.shared
    @State private var selectedSpot: APIClient.APISpot? = nil

    // Activities mode filters — chip selects one kind, sheet tunes the radius.
    @State private var activityKind: ActivityKind = .all
    @State private var activityMaxKm: Double = 5.0
    @State private var showActivityFiltersSheet: Bool = false

    /// First-class sport / spot kind used as the top chips of the Activities
    /// mode. Maps to one or more `tagline` values on the backend, matched
    /// case-insensitively. Order follows the most-asked sports first.
    enum ActivityKind: String, CaseIterable, Identifiable {
        case all, padel, tennis, football, basketball, gym, yoga, skate, park
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:        return "All"
            case .padel:      return "Padel"
            case .tennis:     return "Tennis"
            case .football:   return "Foot 5"
            case .basketball: return "Basket"
            case .gym:        return "Gym"
            case .yoga:       return "Yoga"
            case .skate:      return "Skate"
            case .park:       return "Park"
            }
        }
        var icon: String {
            switch self {
            case .all:        return "square.grid.2x2.fill"
            case .padel:      return "figure.tennis"
            case .tennis:     return "figure.tennis"
            case .football:   return "soccerball"
            case .basketball: return "basketball.fill"
            case .gym:        return "dumbbell.fill"
            case .yoga:       return "figure.yoga"
            case .skate:      return "skateboard.fill"
            case .park:       return "leaf.fill"
            }
        }
        /// Backend `kinds` filter values sent on /v1/spots. Empty = no filter.
        var backendKinds: [String] {
            switch self {
            case .all:        return []
            case .padel:      return ["padel"]
            case .tennis:     return ["tennis"]
            case .football:   return ["football"]
            case .basketball: return ["basketball"]
            case .gym:        return ["gym"]
            case .yoga:       return ["yoga"]
            case .skate:      return ["skatepark"]
            case .park:       return ["park"]
            }
        }
    }

    /// Top-level split of the tab. Events is the primary social/discovery
    /// surface; Activities is the ClassPass-style vertical (padel, gyms,
    /// spots) which has its own content rules and no chips.
    enum ViewMode: String, CaseIterable, Identifiable {
        case events, activities
        var id: String { rawValue }
        var label: String {
            switch self {
            case .events:     return "Events"
            case .activities: return "Activities"
            }
        }
    }

    /// Temporal/scope chip shown inside Events mode. "When" never appears
    /// inside the Filters sheet — the chip is the only temporal selector.
    enum FilterChip: String, CaseIterable, Identifiable {
        case forYou, today, weekend, later, myEvents
        var id: String { rawValue }
        var label: String {
            switch self {
            case .forYou:   return "For you"
            case .today:    return "Today"
            case .weekend:  return "Weekend"
            case .later:    return "Later"
            case .myEvents: return "My events"
            }
        }
        /// Value sent as the `filter=` query param for the events list API.
        /// `.forYou` and `.later` send nothing and let the backend apply its
        /// default 90-day window; the client then filters/ranks locally.
        /// `.myEvents` bypasses the list endpoint entirely.
        var backendFilter: String? {
            switch self {
            case .today:           return "tonight" // reuse existing preset
            case .weekend:         return "weekend"
            case .forYou, .later, .myEvents: return nil
            }
        }
        var sectionTitle: String {
            switch self {
            case .forYou:   return "For you"
            case .today:    return "Today"
            case .weekend:  return "This weekend"
            case .later:    return "Upcoming"
            case .myEvents: return "My events"
            }
        }
    }

    /// Secondary filters — persisted in the Filters sheet.
    @State private var friendsOnly: Bool = false
    @State private var mineOnly: Bool = false
    @State private var showFiltersSheet = false

    /// Active secondary category filters (multi-select). Empty = no filter.
    @State private var activeCategories: Set<String> = []

    struct CategoryChip: Identifiable, Hashable {
        let id: String
        let label: String
        let icon: String
        static let all: [CategoryChip] = [
            .init(id: "clubbing", label: "Clubbing",  icon: "music.note.house.fill"),
            .init(id: "open_air", label: "Open air",  icon: "sun.max.fill"),
            .init(id: "concert",  label: "Concerts",  icon: "guitars.fill"),
            .init(id: "course",   label: "Running",   icon: "figure.run"),
            .init(id: "sport",    label: "Sport",     icon: "sportscourt.fill"),
            .init(id: "food",     label: "Food",      icon: "fork.knife"),
            .init(id: "art",      label: "Art",       icon: "paintpalette.fill"),
        ]
    }

    /// Human-readable label for a backend category string (for the card badge).
    static func prettyCategoryLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw != "other" else { return nil }
        if let chip = CategoryChip.all.first(where: { $0.id == raw }) {
            return chip.label
        }
        return raw.capitalized
    }

    private var selectedCity: APIClient.APICity? {
        guard let id = store.selectedCityId else { return nil }
        return store.cities.first { $0.id == id }
    }

    /// 3-letter city code for the header pill (e.g. "BRU", "PAR", "NYC").
    private var shortCityCode: String {
        guard let name = selectedCity?.name, !name.isEmpty else { return "—" }
        return String(name.uppercased().prefix(3))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            modeSwitch
            if viewMode == .events {
                chips
            }
            content
        }
        .task {
            await bootstrap()
        }
        .onChange(of: store.selectedCityId) { _, _ in scheduleReload() }
        .onChange(of: activeFilter)         { _, _ in scheduleReload() }
        .onChange(of: activeCategories)     { _, _ in scheduleReload() }
        .onChange(of: friendsOnly)          { _, _ in scheduleReload() }
        .onChange(of: viewMode)             { _, _ in scheduleReload() }
        .sheet(isPresented: $showFiltersSheet) {
            EventsFiltersSheet(
                categories: $activeCategories,
                friendsOnly: $friendsOnly
            )
        }
        .onChange(of: searchQuery) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
        .sheet(isPresented: $showCityPicker) {
            CitySelectionSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateEventSheetRemote(onCreated: { _ in
                Task { await reload() }
            })
        }
        .sheet(item: $selectedEvent) { row in
            EventDetailSheetRemote(row: row)
        }
        .sheet(isPresented: $showFullMap) {
            FullMapSheet(
                seedEvents: geolocEvents.items,
                cityId: store.selectedCityId ?? "city_brussels",
                cityName: selectedCity?.name ?? "Brussels",
                parentFilter: activeFilter,
                forYouEvents: Array(forYouPicks.prefix(20)),
                onPick: { row in
                    showFullMap = false
                    selectedEvent = row
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log off")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            headerTopRow
            if showSearchBar {
                searchBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var headerTopRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    showCityPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 15))
                        Text(shortCityCode)
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.bgCard)
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearchBar.toggle()
                        if !showSearchBar { searchQuery = "" }
                    }
                } label: {
                    Image(systemName: showSearchBar ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.bgCard))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showSearchBar ? "Close search" : "Search events")

                Button {
                    showFullMap = true
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.bgCard))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Map")

                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(Theme.text)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create event")
            }
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, showSearchBar ? 4 : 8)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Theme.textFaint)
            TextField("Search events, venues...", text: $searchQuery)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { Task { await reload() } }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.bgCard)
        )
    }

    // MARK: - Filter chips

    private var chips: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterChip.allCases) { chip in
                        chipButton(chip)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 8)
            }
            filtersButton
                .padding(.trailing, 24)
        }
        .padding(.bottom, 12)
    }

    private var filtersButton: some View {
        Button {
            showFiltersSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .bold))
                if activeFiltersCount > 0 {
                    Text("\(activeFiltersCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(Theme.orange))
                }
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.bgCard))
        }
        .buttonStyle(.plain)
    }

    private var activeFiltersCount: Int {
        var n = activeCategories.count
        if friendsOnly { n += 1 }
        return n
    }

    private func chipButton(_ chip: FilterChip) -> some View {
        let active = activeFilter == chip
        return Button {
            activeFilter = chip
        } label: {
            Text(chip.label)
                .font(.system(size: 14, weight: active ? .bold : .semibold))
                .foregroundColor(active ? .white : Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(active ? Theme.text : Theme.bgCard)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if loading && !loaded {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading...")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else if viewMode == .activities {
            activitiesModeContent
        } else {
            eventsModeContent
        }
    }

    /// Single vertical feed of big event cards. Content depends on the active
    /// chip — For You is a 20-pick curation, Today/Weekend/Later are the full
    /// filtered list, My events is the user's created + RSVP'd list.
    @ViewBuilder
    private var eventsModeContent: some View {
        switch activeFilter {
        case .forYou:
            bigCardsFeed(Array(forYouPicks.prefix(20)))
        case .today:
            bigCardsFeed(tonightEvents)
        case .weekend:
            bigCardsFeed(weekendEvents)
        case .later:
            bigCardsFeed(laterEvents)
        case .myEvents:
            myEventsContent
        }
    }

    /// "Later" = every upcoming event except those already surfaced by the
    /// Today or Weekend chips. That means: date ≥ tomorrow-05:00 AND the
    /// event does not fall inside this weekend's [Fri 18:00, Mon 04:00] slice.
    /// This closes the Wed/Thu/Fri-afternoon gap the previous `>= weekendEnd`
    /// filter had (events mid-week would fall into no chip at all).
    private var laterEvents: [APIClient.APIEventListRow] {
        let now = Date()
        let cal = Calendar.current
        let todayEnd = cal.date(byAdding: .day, value: 1, to: now)
            .flatMap { cal.date(bySettingHour: 5, minute: 0, second: 0, of: $0) } ?? now
        let (weekendStart, weekendEnd) = Self.weekendWindow(from: now)

        let pool = (heroEvents + friendsEvents + weekEvents).reduce(into: [APIClient.APIEventListRow]()) { acc, row in
            if !acc.contains(where: { $0.id == row.id }) { acc.append(row) }
        }
        return pool
            .filter { row in
                guard row.date >= todayEnd else { return false }       // not today
                if row.date >= weekendStart && row.date < weekendEnd { // not weekend
                    return false
                }
                return true
            }
            .sorted { $0.date < $1.date }
    }

    /// Vertical scroll of full-width hero cards. Empty state when the list is
    /// empty. Adds the map hint / refine button at the bottom.
    @ViewBuilder
    private func bigCardsFeed(_ events: [APIClient.APIEventListRow]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if events.isEmpty && loaded {
                    emptyState.padding(.top, 40)
                } else {
                    ForEach(events) { row in
                        eventCardHero(row)
                            .onTapGesture { selectedEvent = row }
                    }
                }
                Spacer().frame(height: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    /// Activities mode = ClassPass / Playtomic-style vertical. Chips pick the
    /// activity kind (Padel / Tennis / Gym / Yoga…), the filter sheet tunes
    /// the radius, and results are sorted by server-computed distance when
    /// the user has granted location access.
    @ViewBuilder
    private var activitiesModeContent: some View {
        VStack(spacing: 0) {
            activityKindChips
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if !locationManager.isAuthorized {
                        locationPromptCard
                            .padding(.horizontal, 24)
                    }
                    if spotsStore.spots.isEmpty && loaded {
                        emptyState.padding(.top, 40)
                    } else {
                        VStack(spacing: 14) {
                            ForEach(spotsStore.spots) { spot in
                                activitySpotCard(spot)
                                    .onTapGesture { selectedSpot = spot }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.top, 8)
            }
        }
        .task(id: activityLoadKey) {
            await reloadActivities()
        }
        .onChange(of: locationManager.location) { _, _ in
            Task { await reloadActivities() }
        }
        .sheet(isPresented: $showActivityFiltersSheet) {
            activityFiltersSheet
        }
    }

    /// Cache-busting key: any of these changing triggers a fresh load.
    private var activityLoadKey: String {
        let city = store.selectedCityId ?? ""
        let kind = activityKind.rawValue
        let km = String(Int(activityMaxKm))
        return "\(city)|\(kind)|\(km)|\(locationManager.isAuthorized ? "loc" : "noloc")"
    }

    private func reloadActivities() async {
        let cityId = store.selectedCityId ?? "city_brussels"
        await spotsStore.loadSpots(
            cityId: cityId,
            kinds: activityKind.backendKinds,
            userLat: locationManager.location?.coordinate.latitude,
            userLng: locationManager.location?.coordinate.longitude,
            maxKm: locationManager.isAuthorized ? activityMaxKm : nil,
            forceRefresh: true
        )
    }

    /// Horizontal chip strip of activity kinds + filters button on the right.
    private var activityKindChips: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ActivityKind.allCases) { kind in
                        let active = activityKind == kind
                        Button {
                            activityKind = kind
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: 11, weight: .bold))
                                Text(kind.label)
                                    .font(.system(size: 14, weight: active ? .bold : .semibold))
                            }
                            .foregroundColor(active ? .white : Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? Theme.text : Theme.bgCard))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 8)
            }
            Button {
                showActivityFiltersSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .bold))
                    if locationManager.isAuthorized {
                        Text("\(Int(activityMaxKm))km")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.bgCard))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
        }
        .padding(.bottom, 12)
    }

    /// Banner shown when the user hasn't yet granted location. Makes the
    /// value of "near me" explicit before asking — trivial difference in
    /// grant rate vs. the bare system prompt.
    private var locationPromptCard: some View {
        Button {
            locationManager.requestPermission()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show what's near you")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("Allow location to sort by distance")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard))
        }
        .buttonStyle(.plain)
    }

    /// Radius + future filters. Kept deliberately short — one slider today,
    /// room to grow (indoor/outdoor, price, open-now) later without a redesign.
    private var activityFiltersSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Distance")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text("Only show places within \(Int(activityMaxKm)) km")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                        Slider(value: $activityMaxKm, in: 1...25, step: 1)
                            .tint(Theme.orange)
                        HStack {
                            Text("1 km")
                            Spacer()
                            Text("25 km")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bgCard))

                    if !locationManager.isAuthorized {
                        Text("Location access needed for radius filtering. Tap the banner on the main screen to enable it.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .background(Theme.bg)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showActivityFiltersSheet = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Compact spot card sized for the Activities list: big image, tagline,
    /// distance pill, and a Book button that deep-links to the closest
    /// booking platform (Playtomic for padel/tennis, Mindbody for gyms/yoga,
    /// Apple Maps otherwise).
    private func activitySpotCard(_ spot: APIClient.APISpot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let url = URL(string: spot.imageUrl), !spot.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.16, blue: 0.22), Color(red: 0.22, green: 0.16, blue: 0.24)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: kindIconForSpot(spot))
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.4))
                    )
                }
                if let dist = spot.distanceKm {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 9))
                        Text(String(format: "%.1f km", dist))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(10)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(spot.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !spot.tagline.isEmpty {
                    Text(spot.tagline)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let rating = spot.rating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                            Text(String(format: "%.1f", rating)).font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Theme.orange)
                    }
                    Spacer()
                    bookButton(for: spot)
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    /// Routes each spot kind to its best booking platform. Padel/tennis →
    /// Playtomic search (they cover the vast majority of clubs in EU cities).
    /// Gym/yoga → the spot's own website if set (Mindbody API integration is
    /// Phase 2). Everything else → Apple Maps so users can at least navigate.
    private func bookButton(for spot: APIClient.APISpot) -> some View {
        let action = bookAction(for: spot)
        return Button {
            if let url = action.url {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(action.label)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(action.bgColor))
        }
        .buttonStyle(.plain)
    }

    private struct BookAction {
        let label: String
        let icon: String
        let bgColor: Color
        let url: URL?
    }

    private func bookAction(for spot: APIClient.APISpot) -> BookAction {
        let tag = spot.tagline.lowercased()
        if tag.contains("padel") || tag.contains("tennis") {
            let sport = tag.contains("padel") ? "padel" : "tennis"
            let url = URL(string: "https://playtomic.io/search?sport=\(sport)&lat=\(spot.lat)&lng=\(spot.lng)")
            return BookAction(label: "Book", icon: "calendar.badge.plus", bgColor: Theme.orange, url: url)
        }
        if !spot.websiteUrl.isEmpty, let url = URL(string: spot.websiteUrl) {
            return BookAction(label: "Website", icon: "arrow.up.right.square", bgColor: Theme.text, url: url)
        }
        let label = spot.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://maps.apple.com/?ll=\(spot.lat),\(spot.lng)&q=\(label)")
        return BookAction(label: "Map", icon: "map.fill", bgColor: Theme.text, url: url)
    }

    private func kindIconForSpot(_ spot: APIClient.APISpot) -> String {
        let tag = spot.tagline.lowercased()
        if tag.contains("padel") || tag.contains("tennis") { return "figure.tennis" }
        if tag.contains("football") || tag.contains("foot") { return "soccerball" }
        if tag.contains("basket") { return "basketball.fill" }
        if tag.contains("gym") || tag.contains("fitness") { return "dumbbell.fill" }
        if tag.contains("yoga") || tag.contains("pilates") { return "figure.yoga" }
        if tag.contains("skate") { return "skateboard.fill" }
        if tag.contains("park") { return "leaf.fill" }
        return "mappin.circle.fill"
    }

    /// Full-width hero card for an activity (padel, yoga, etc.). Same visual
    /// weight as `eventCardHero` so the two modes feel consistent.
    private func activityBigCard(_ act: APIClient.APIActivity) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let url = URL(string: act.imageUrl), !act.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Theme.green.opacity(0.75), Theme.orange.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "figure.run")
                            .font(.system(size: 38))
                            .foregroundColor(.white.opacity(0.8))
                    )
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(act.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !act.description.isEmpty {
                    Text(act.description)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(act.category.capitalized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.green))
                    if let mins = act.durationMinutes {
                        Text("\(mins) min")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Mode switch (Events | Activities)

    /// Big visual split at the top of the tab — mirrors the App Store's
    /// Today/Games/Apps switch. Two pills, equal width, clear active state.
    private var modeSwitch: some View {
        HStack(spacing: 8) {
            ForEach(ViewMode.allCases) { m in
                let active = viewMode == m
                Button {
                    viewMode = m
                } label: {
                    Text(m.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(active ? .white : Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(active ? Theme.text : Theme.bgCard)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    /// Events happening before tomorrow 05:00 (classic "tonight" window).
    private var tonightEvents: [APIClient.APIEventListRow] {
        let now = Date()
        let cal = Calendar.current
        let cutoff = cal.date(bySettingHour: 5, minute: 0, second: 0,
                              of: cal.date(byAdding: .day, value: 1, to: now) ?? now) ?? now
        let pool = heroEvents + friendsEvents + weekEvents
        var seen = Set<String>()
        return pool
            .filter { seen.insert($0.id).inserted }
            .filter { $0.date >= now && $0.date < cutoff }
            .sorted { $0.date < $1.date }
    }

    /// Events between the current-or-upcoming Friday 18:00 and Monday 04:00.
    /// Handles the Sat/Sun case where "this weekend" == today, not next week.
    private var weekendEvents: [APIClient.APIEventListRow] {
        let (start, end) = Self.weekendWindow(from: Date())
        let pool = heroEvents + friendsEvents + weekEvents
        var seen = Set<String>()
        return pool
            .filter { seen.insert($0.id).inserted }
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// Computes [Fri 18:00, Mon 04:00] relative to `now`. If we're already
    /// inside that window, returns (now, Mon 04:00). Past Mon 04:00 jumps to
    /// next weekend. Exposed `static` for reuse in tests / the map sheet.
    static func weekendWindow(from now: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1=Sun..7=Sat
        let offsetToThisFri: Int = {
            switch weekday {
            case 1: return -2  // Sunday
            case 2: return 4
            case 3: return 3
            case 4: return 2
            case 5: return 1
            case 6: return 0
            case 7: return -1
            default: return 0
            }
        }()
        let fri = cal.date(byAdding: .day, value: offsetToThisFri, to: now)
            .flatMap { cal.date(bySettingHour: 18, minute: 0, second: 0, of: $0) } ?? now
        let mon = cal.date(byAdding: .day, value: 3, to: fri)
            .flatMap { cal.date(bySettingHour: 4, minute: 0, second: 0, of: $0) } ?? now
        if now >= mon {
            let nextFri = cal.date(byAdding: .day, value: 7, to: fri) ?? fri
            let nextMon = cal.date(byAdding: .day, value: 3, to: nextFri)
                .flatMap { cal.date(bySettingHour: 4, minute: 0, second: 0, of: $0) } ?? nextFri
            return (nextFri, nextMon)
        }
        return (max(now, fri), mon)
    }

    @ViewBuilder
    private func timeFilteredFeed(title: String, events: [APIClient.APIEventListRow]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)
                if events.isEmpty && loaded {
                    emptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(events) { row in
                            eventCardHero(row)
                                .onTapGesture { selectedEvent = row }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                Spacer().frame(height: 80)
            }
            .padding(.top, 4)
        }
    }

    /// Curated picks for "Pour toi". Scoring:
    ///   +10 for each friend going (social proof is the strongest signal)
    ///   +1  if date is within the next 7 days (freshness)
    ///   +1  if date is today or tomorrow (urgency)
    /// Ties broken by earliest date first. Returns up to 10 events.
    private var forYouPicks: [APIClient.APIEventListRow] {
        let pool = heroEvents + friendsEvents + weekEvents
        var seen = Set<String>()
        let dedup = pool.filter { seen.insert($0.id).inserted }
        let now = Date()
        let in7d = now.addingTimeInterval(7 * 24 * 3600)
        let in48h = now.addingTimeInterval(48 * 3600)
        let scored = dedup.map { row -> (APIClient.APIEventListRow, Int) in
            var score = row.friendsGoingCount * 10
            if row.date >= now && row.date <= in7d { score += 1 }
            if row.date >= now && row.date <= in48h { score += 1 }
            return (row, score)
        }
        let sorted = scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.date < b.0.date
        }
        return sorted.prefix(10).map { $0.0 }
    }

    // MARK: - Unified 6-section feed (Pass B)

    /// Single-scroll feed composed of 6 dedicated sections. Replaces the old
    /// mode-based views (forYou / activities / all / past) with one coherent
    /// composition anchored by the active time chip.
    ///
    /// Order is deliberate: social proof first (For You, With Friends), then
    /// the main discovery list (Sortir), then activity verticals (Bouger,
    /// Spots), then sponsored content at the bottom.
    @ViewBuilder
    private var unifiedFeed: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                sectionForYou
                sectionFriends
                sectionSortir
                sectionBouger
                sectionSpots
                sectionPartenaires
                Spacer().frame(height: 80)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var sectionForYou: some View {
        let picks = forYouPicks
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("For you", subtitle: "Based on your friends and what's hot")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(picks) { row in
                            compactEventCard(row)
                                .onTapGesture { selectedEvent = row }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var sectionFriends: some View {
        let withFriends = friendsEvents.filter { $0.friendsGoingCount > 0 }
        if !withFriends.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("With your friends", subtitle: "Where your crew is going")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(withFriends) { row in
                            compactEventCard(row)
                                .onTapGesture { selectedEvent = row }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    /// Vertical list — the main discovery surface. Kept as full-size hero
    /// cards so the primary action (go out) is visually dominant.
    @ViewBuilder
    private var sectionSortir: some View {
        let pool = (heroEvents + weekEvents).reduce(into: [APIClient.APIEventListRow]()) { acc, row in
            if !acc.contains(where: { $0.id == row.id }) { acc.append(row) }
        }
        if !pool.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(activeFilter.sectionTitle, subtitle: "Clubs, concerts, open air")
                    .padding(.horizontal, 0)
                VStack(spacing: 14) {
                    ForEach(pool.prefix(15)) { row in
                        eventCardHero(row)
                            .onTapGesture { selectedEvent = row }
                    }
                }
                .padding(.horizontal, 24)
                moreEventsLink
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var sectionBouger: some View {
        let acts = activitiesStore.activities
        if !acts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Move", subtitle: "Padel, tennis, gyms, yoga")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(acts.prefix(12)) { act in
                            compactActivityCard(act)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var sectionSpots: some View {
        let sp = spotsStore.spots
        if !sp.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Spots", subtitle: "Places worth putting your phone down for")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sp.prefix(12)) { spot in
                            compactSpotCard(spot)
                                .onTapGesture { selectedSpot = spot }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    /// Bottom-anchored sponsored slot. Kept visually distinct but native —
    /// no real partner yet, so the card is a placeholder CTA surfaced only
    /// to prove the layout and make the business space obvious.
    @ViewBuilder
    private var sectionPartenaires: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Partners", subtitle: "Curated by places we love")
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.orange.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your spot here")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("We're onboarding partner venues — coming soon")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bgCard))
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Section header + compact cards

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, 24)
    }

    /// 220×240 card used inside horizontal carousels. Image on top, two-line
    /// info beneath. Lighter than `eventCardHero` so you can scan 5+ at a
    /// glance without a wall of text.
    private func compactEventCard(_ row: APIClient.APIEventListRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heroImageBlock(row)
                .frame(width: 220, height: 140)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(formatDateShort(row.date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                if row.friendsGoingCount > 0 {
                    Text("\(row.friendsGoingCount) friend\(row.friendsGoingCount > 1 ? "s" : "") going")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.orange)
                }
            }
            .padding(10)
            .frame(width: 220, alignment: .leading)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func compactSpotCard(_ spot: APIClient.APISpot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let url = URL(string: spot.imageUrl), !spot.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(width: 180, height: 140)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.16, blue: 0.22), Color(red: 0.22, green: 0.16, blue: 0.24)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 180, height: 140)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(spot.category.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func compactActivityCard(_ act: APIClient.APIActivity) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let url = URL(string: act.imageUrl), !act.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(width: 180, height: 140)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Theme.green.opacity(0.7), Theme.orange.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 180, height: 140)
                    .overlay(
                        Image(systemName: "figure.run")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.8))
                    )
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(act.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(act.category.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.4), lineWidth: 0.5)
        )
    }

    /// Curated picks in big attractive cards, vertical stack. No map, no
    /// horizontal scroll. Discreet "More events" link at the bottom.
    @ViewBuilder
    private var forYouFeed: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                forYouHeader
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)

                if forYouPicks.isEmpty && loaded {
                    emptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(forYouPicks) { row in
                            eventCardHero(row)
                                .onTapGesture { selectedEvent = row }
                        }
                    }
                    .padding(.horizontal, 24)

                    if !forYouPicks.isEmpty {
                        moreEventsLink
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var activitiesFeed: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activities")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("Spots to do something else than scroll")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 2)

                if spotsStore.isLoading && spotsStore.spots.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if spotsStore.spots.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 30))
                            .foregroundColor(Theme.textFaint)
                        Text("No activities loaded yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 14) {
                        ForEach(spotsStore.spots) { spot in
                            spotCard(spot)
                                .onTapGesture { selectedSpot = spot }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                Spacer().frame(height: 80)
            }
            .padding(.top, 4)
        }
        .task(id: store.selectedCityId ?? "") {
            await spotsStore.loadSpots(
                cityId: store.selectedCityId ?? "city_brussels",
                categories: [],
                query: "",
                forceRefresh: false
            )
        }
        .sheet(item: $selectedSpot) { spot in
            SpotDetailSheet(spot: spot)
        }
    }

    private func spotCard(_ spot: APIClient.APISpot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    SwiftUI.Group {
                        if let url = URL(string: spot.imageUrl), !spot.imageUrl.isEmpty {
                            CachedAsyncImage(url: url)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.16, blue: 0.22), Color(red: 0.22, green: 0.16, blue: 0.24)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .overlay(
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.3))
                            )
                        }
                    }
                }
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        overlayPill(spot.category.uppercased(), color: .white, bg: Theme.green.opacity(0.85))
                        Spacer()
                        if let rating = spot.rating, rating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 10))
                                Text(String(format: "%.1f", rating)).font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !spot.tagline.isEmpty {
                    Text(spot.tagline)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                } else if !spot.address.isEmpty {
                    Text(spot.address)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var forYouHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("For you")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
            Text("Based on your friends and what's popular")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Discreet text link — opens the filter sheet so the user can broaden
    /// their search. Previously toggled a mode; in the 3-chip model there's
    /// nothing to toggle to.
    private var moreEventsLink: some View {
        Button {
            showFiltersSheet = true
        } label: {
            HStack(spacing: 4) {
                Text("Refine")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Theme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    /// Big hero-style card used on "For you". Image on top (180pt), info
    /// block beneath, wrapped in a single rounded card so each event has a
    /// clear visual boundary.
    private func eventCardHero(_ row: APIClient.APIEventListRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heroImageBlock(row)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()

            heroInfoBlock(row)
                .padding(14)
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func heroImageBlock(_ row: APIClient.APIEventListRow) -> some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                SwiftUI.Group {
                    if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                        CachedAsyncImage(url: url)
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.12, blue: 0.2), Color(red: 0.2, green: 0.1, blue: 0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.22))
                        )
                    }
                }
            }

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if row.source == "ra" {
                        overlayPill("RA", color: .white.opacity(0.9), bg: .black.opacity(0.55))
                    }
                    if let cat = Self.prettyCategoryLabel(row.category) {
                        overlayPill(cat, color: .white, bg: Theme.orange.opacity(0.85))
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
                HStack {
                    Text(formatDateHero(row.date))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                    Spacer()
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func heroInfoBlock(_ row: APIClient.APIEventListRow) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textFaint)
                        Text(row.location)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if row.friendsGoingCount > 0 {
                friendsGoingClusterBR(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bottom-right friend cluster: up to 3 photo-circles, then a "+N" pill
    /// if more. Replaces the on-image overlay so the photo stays clean.
    private func friendsGoingClusterBR(_ row: APIClient.APIEventListRow) -> some View {
        let names = row.friendNames
        let ids = row.friendIds ?? []
        let shown = min(names.count, 3)
        let extra = row.friendsGoingCount - shown
        return HStack(spacing: -8) {
            ForEach(0..<shown, id: \.self) { i in
                FriendPhotoCircle(
                    uid: ids[safe: i] ?? "",
                    name: names[i],
                    size: 26
                )
                .overlay(Circle().strokeBorder(Theme.bgCard, lineWidth: 2))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.text))
                    .overlay(Circle().strokeBorder(Theme.bgCard, lineWidth: 2))
            }
        }
    }

    private func overlayPill(_ text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }

    private func formatDateHero(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE d MMM · HH:mm"
        return formatter.string(from: date).uppercased()
    }

    // Tous = full list. Filter button + chronological vertical feed.
    @ViewBuilder
    private var allFeed: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                allFeedControls
                if mineOnly {
                    mineBanner
                }
                allEventsList
                Spacer().frame(height: 80)
            }
            .padding(.top, 4)
        }
    }

    /// Banner shown at the top of Tous when My events is active. Gives an
    /// explicit exit back to "For you".
    private var mineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.orange)
            Text("Viewing your events only")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer()
            Button {
                mineOnly = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text)
                    .padding(6)
                    .background(Circle().fill(Theme.bgCard))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.orange.opacity(0.12)))
        .padding(.horizontal, 24)
    }

    private var allFeedControls: some View {
        HStack {
            Spacer()
            filtersButton
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var allEventsList: some View {
        let pool = heroEvents + friendsEvents + weekEvents
        var seen = Set<String>()
        let dedup = pool.filter { seen.insert($0.id).inserted }
            .sorted { $0.date < $1.date }
        if dedup.isEmpty && loaded {
            emptyState
        } else {
            VStack(spacing: 10) {
                ForEach(dedup) { row in
                    eventCardM(row)
                        .onTapGesture { selectedEvent = row }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Past events ("J'y étais") with KPIs at top

    @ViewBuilder
    private var pastEventsContent: some View {
        if weekEvents.isEmpty && loaded {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.textFaint)
                Text("No attended events yet").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                Text("RSVP to events and they'll show up here after.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                pastKPIs
                VStack(spacing: 10) {
                    ForEach(weekEvents) { row in
                        eventCardM(row).onTapGesture { selectedEvent = row }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 4)
        }
    }

    private var pastKPIs: some View {
        let total = weekEvents.count
        let countsByCat = Dictionary(grouping: weekEvents, by: { $0.category ?? "other" })
            .mapValues { $0.count }
        let topCat = countsByCat.sorted { $0.value > $1.value }.first?.key
        let topCatLabel = Self.prettyCategoryLabel(topCat) ?? "—"
        let ragoutFriends: Int = weekEvents.reduce(0) { $0 + $1.friendsGoingCount }

        return HStack(spacing: 12) {
            kpiCard(value: "\(total)", label: "Events")
            kpiCard(value: topCatLabel, label: "Top category")
            kpiCard(value: "\(ragoutFriends)", label: "Friends seen")
        }
        .padding(.horizontal, 24)
    }

    private func kpiCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
        )
    }

    // MARK: - Map

    /// Geolocated events to show on the map. Priority:
    /// 1. Events happening TODAY (local calendar)
    /// 2. If empty → any upcoming geolocated event within 7 days
    /// Ensures the map is almost always visible when there's *something* near.
    private var geolocEvents: (items: [APIClient.APIEventListRow], isToday: Bool) {
        let cal = Calendar.current
        let pool = heroEvents + friendsEvents + weekEvents
        var seen = Set<String>()
        let geo = pool.filter { row in
            guard let lat = row.venueLat, let lng = row.venueLng,
                  lat != 0 || lng != 0 else { return false }
            return seen.insert(row.id).inserted
        }
        let todayItems = geo.filter { cal.isDateInToday($0.date) }
        if !todayItems.isEmpty {
            return (todayItems, true)
        }
        let soon = geo
            .filter { $0.date >= Date() }
            .sorted { $0.date < $1.date }
            .prefix(20)
        return (Array(soon), false)
    }

    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var mapExpanded = false

    @ViewBuilder
    private var eventsMapSection: some View {
        let (items, isToday) = geolocEvents
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(isToday
                         ? "Today in \(selectedCity?.name ?? "your city")"
                         : "Upcoming in \(selectedCity?.name ?? "your city")")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("\(items.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.orange.opacity(0.14)))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { mapExpanded.toggle() }
                    } label: {
                        Image(systemName: mapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.text)
                            .padding(8)
                            .background(Circle().fill(Theme.bgCard))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Map(position: $mapCameraPosition) {
                    ForEach(items) { row in
                        Annotation(row.title, coordinate: CLLocationCoordinate2D(
                            latitude: row.venueLat ?? 0,
                            longitude: row.venueLng ?? 0
                        )) {
                            Button { selectedEvent = row } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white, Theme.orange)
                                        .shadow(radius: 2)
                                    Text(row.title)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Theme.text)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.bg.opacity(0.85)))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: mapExpanded ? 380 : 170)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                .onAppear { fitMapToEvents(items) }
                .onChange(of: items.map(\.id)) { _, _ in fitMapToEvents(items) }
            }
        }
    }

    private func fitMapToEvents(_ items: [APIClient.APIEventListRow]) {
        guard !items.isEmpty else { return }
        let coords = items.compactMap { row -> CLLocationCoordinate2D? in
            guard let lat = row.venueLat, let lng = row.venueLng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard let first = coords.first else { return }
        if coords.count == 1 {
            mapCameraPosition = .region(MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
            return
        }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.3, 0.01)
        )
        mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Popular section (sorted by friendsGoingCount desc)

    @ViewBuilder
    private var popularSection: some View {
        let pool = (heroEvents + friendsEvents + weekEvents)
        var seen = Set<String>()
        let dedup = pool.filter { seen.insert($0.id).inserted }
        let popular = dedup
            .filter { $0.friendsGoingCount > 0 }
            .sorted { $0.friendsGoingCount > $1.friendsGoingCount }
            .prefix(10)
        if !popular.isEmpty {
            horizontalShelf(
                title: "Popular nearby",
                subtitle: "The hottest events around",
                items: Array(popular)
            )
        }
    }

    // MARK: - My Events content (when My Events chip is active)

    @ViewBuilder
    private var myEventsContent: some View {
        if myEvents.isEmpty && loaded {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.textFaint)
                Text("No events yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                Text("RSVP to events or create your own")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else {
            VStack(alignment: .leading, spacing: 28) {
                sectionHeader(title: "My events", subtitle: nil)
                VStack(spacing: 10) {
                    ForEach(myEvents) { ev in
                        myEventCard(ev)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 4)
        }
    }

    private func myEventCard(_ ev: APIClient.APIUserEvent) -> some View {
        Button {
            Task {
                if let detail = await store.fetchDetail(id: ev.id) {
                    selectedEvent = APIClient.APIEventListRow(
                        id: detail.id, title: detail.title, description: detail.description,
                        date: detail.date, endDate: detail.endDate, location: detail.location,
                        address: detail.address, source: detail.source, sourceUrl: detail.sourceUrl,
                        imageUrl: detail.imageUrl, cityId: detail.cityId, venueLat: detail.venueLat,
                        venueLng: detail.venueLng, visibility: detail.visibility, creatorId: detail.creatorId,
                        category: detail.category,
                        myRsvp: detail.myRsvp, friendsGoingCount: detail.friendsGoingCount,
                        friendNames: detail.friendNames, friendIds: detail.friendIds
                    )
                }
            }
        } label: {
            HStack(spacing: 12) {
                SwiftUI.Group {
                    if let url = URL(string: ev.imageUrl), !ev.imageUrl.isEmpty {
                        CachedAsyncImage(url: url)
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color(red: 0.15, green: 0.15, blue: 0.22), Color(red: 0.22, green: 0.12, blue: 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDateShort(ev.date))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.orange)
                        .tracking(0.4)

                    Text(ev.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !ev.location.isEmpty {
                        Text(ev.location)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Text(ev.status == "going" ? "Going" : "Interested")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ev.status == "going" ? Theme.green : Theme.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill((ev.status == "going" ? Theme.green : Theme.orange).opacity(0.12))
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.bgCard)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 40))
                .foregroundColor(Theme.textFaint)
            Text("No events for this filter")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textMuted)
            Text("Try another city or filter")
                .font(.system(size: 13))
                .foregroundColor(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Hero section (XL horizontal scroll, Apple-Music-sized)

    @ViewBuilder
    private var heroSection: some View {
        if !heroEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "This weekend in \(selectedCity?.name ?? "Brussels")",
                    subtitle: nil
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(heroEvents.prefix(10)) { row in
                            eventCardXL(row)
                                .onTapGesture { selectedEvent = row }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 24)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: - Friends section (compact horizontal)

    @ViewBuilder
    private var friendsSection: some View {
        if !friendsEvents.isEmpty {
            horizontalShelf(
                title: "Your friends are going",
                subtitle: nil,
                items: Array(friendsEvents.prefix(12))
            )
        }
    }

    // MARK: - Week section (compact horizontal)

    @ViewBuilder
    private var weekSection: some View {
        if !weekEvents.isEmpty {
            horizontalShelf(
                title: activeFilter.sectionTitle,
                subtitle: nil,
                items: Array(weekEvents.prefix(15))
            )
        }
    }

    /// Apple-Music-style horizontal shelf: compact 160pt cards scrolling with
    /// snap alignment. Used by friends / popular / week sections.
    @ViewBuilder
    private func horizontalShelf(title: String, subtitle: String?, items: [APIClient.APIEventListRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { row in
                        eventCardCompact(row)
                            .onTapGesture { selectedEvent = row }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.text)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Event card XL (hero, 280×340)

    private func eventCardXL(_ row: APIClient.APIEventListRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image hero
            ZStack(alignment: .topLeading) {
                if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(width: 220, height: 150)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.12, blue: 0.2), Color(red: 0.2, green: 0.1, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 280, height: 180)
                    .overlay(
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.25))
                    )
                }

                // Source badge
                if row.source == "ra" {
                    Text("RA")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.0)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Info block
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDateShort(row.date))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .tracking(0.4)

                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.location.isEmpty {
                    Text(row.location)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    friendsGoingBadge(row)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 220, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.bgCard)
        )
    }

    // MARK: - Event card Compact (horizontal shelf, 160×230)

    /// Vertical card sized for horizontal shelves. Image on top, title +
    /// date + one line of meta below. Used by friends / popular / week
    /// shelves to keep each one scrollable left/right.
    private func eventCardCompact(_ row: APIClient.APIEventListRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                SwiftUI.Group {
                    if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                        CachedAsyncImage(url: url)
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color(red: 0.14, green: 0.14, blue: 0.22), Color(red: 0.22, green: 0.1, blue: 0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay(
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.22))
                        )
                    }
                }
                .frame(width: 160, height: 140)
                .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .frame(maxWidth: .infinity, alignment: .bottom)

                HStack(spacing: 4) {
                    friendsGoingBadge(row)
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(formatDateShort(row.date))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .tracking(0.4)
                Text(row.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.location.isEmpty {
                    Text(row.location)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 160, height: 230)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
        )
    }

    // MARK: - Event card M (stacked list row, kept for past/mine)

    private func eventCardM(_ row: APIClient.APIEventListRow) -> some View {
        HStack(spacing: 12) {
            // Thumbnail — use SwiftUI.Group explicitly because the PAKT codebase
            // has a custom Group struct for screen-time groups that shadows it.
            SwiftUI.Group {
                if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.15, blue: 0.22), Color(red: 0.22, green: 0.12, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDateShort(row.date))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .tracking(0.4)

                Text(row.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.location.isEmpty {
                    Text(row.location)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    categoryBadge(row.category)
                    friendsGoingBadge(row)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
    }

    @ViewBuilder
    private func categoryBadge(_ raw: String?) -> some View {
        if let label = Self.prettyCategoryLabel(raw) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.orange.opacity(0.14)))
        } else {
            EmptyView()
        }
    }

    /// Row of friend avatars going (green ring) on the event cards. Photo
    /// when available, initial as fallback. No text.
    @ViewBuilder
    private func friendsGoingBadge(_ row: APIClient.APIEventListRow) -> some View {
        if row.friendsGoingCount > 0 && !row.friendNames.isEmpty {
            HStack(spacing: -6) {
                ForEach(Array(row.friendNames.prefix(4).enumerated()), id: \.offset) { idx, name in
                    let uid = (row.friendIds ?? [])[safe: idx] ?? ""
                    FriendPhotoCircle(uid: uid, name: name, size: 22)
                        .overlay(Circle().strokeBorder(Theme.bgCard, lineWidth: 1.5))
                }
                if row.friendsGoingCount > 4 {
                    Circle()
                        .fill(Theme.text)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Text("+\(row.friendsGoingCount - 4)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .overlay(Circle().strokeBorder(Theme.bgCard, lineWidth: 1.5))
                }
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Data loading

    private func bootstrap() async {
        if store.cities.isEmpty {
            await store.loadCities()
        }
        if store.selectedCityId == nil {
            // Default to Brussels. Geoloc-based suggestion is P1.
            store.selectedCityId = "city_brussels"
        }
        if !loaded {
            await reload()
        }
    }

    /// Coalesces rapid filter/city/mode flips into a single reload after a
    /// short debounce window. Avoids the 6-requests-per-tap amplification.
    private func scheduleReload() {
        reloadDebounce?.cancel()
        reloadDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func reload() async {
        guard let cityId = store.selectedCityId else { return }
        loading = true
        lastError = nil
        defer {
            loading = false
            loaded = true
        }

        // My events chip — bypass the list endpoint. Uses the backend
        // user-events endpoint which now includes events I created (since the
        // creator is auto-RSVP'd as `going` in the same transaction).
        if activeFilter == .myEvents {
            let uid = AuthManager.shared.currentUser?.id ?? ""
            if !uid.isEmpty {
                myEvents = await EventManager.shared.fetchUserEvents(userId: uid)
            }
            heroEvents = []
            friendsEvents = []
            weekEvents = []
            store.invalidateDetailCache()
            return
        }

        myEvents = []

        let now = Date()
        let longWindowEnd = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now
        let q = searchQuery.isEmpty ? nil : searchQuery
        let currentFilter = activeFilter
        let cats = Array(activeCategories)
        let onlyFriends = friendsOnly

        // For You and Later both need the full 90d window so the local ranking
        // / time-slice logic has enough material to work with. Today and
        // Weekend use the backend presets for a tighter fetch.
        let useBroadWindow = (currentFilter == .forYou || currentFilter == .later)

        async let main: [APIClient.APIEventListRow] = {
            if useBroadWindow {
                return await store.fetchEvents(
                    cityId: cityId,
                    query: q,
                    from: now,
                    to: longWindowEnd,
                    friendsOnly: onlyFriends,
                    categories: cats,
                    limit: 100
                )
            } else {
                return await store.fetchEvents(
                    cityId: cityId,
                    filter: currentFilter.backendFilter,
                    query: q,
                    friendsOnly: onlyFriends,
                    categories: cats,
                    limit: 100
                )
            }
        }()

        async let hero = store.fetchEvents(
            cityId: cityId,
            filter: "weekend",
            query: q,
            categories: cats,
            limit: 8
        )

        async let friends = store.fetchEvents(
            cityId: cityId,
            query: q,
            from: now,
            to: longWindowEnd,
            friendsOnly: true,
            categories: cats,
            limit: 10
        )

        let (mainResult, heroResult, friendsResult) = await (main, hero, friends)
        weekEvents = mainResult
        heroEvents = heroResult
        friendsEvents = friendsResult

        // Fire spot + activity loads in the background. They're independent of
        // the time chip and cached by their own stores, so we don't block the
        // feed on them — the sections render empty until the fetch completes.
        Task {
            await spotsStore.loadSpots(cityId: cityId, categories: [], query: "", forceRefresh: false)
        }
        Task {
            await activitiesStore.load(cityId: cityId)
        }
        // After a fresh list fetch, detail cache may be stale (friend RSVPs
        // might have changed server-side). Drop it so the next open re-pulls.
        store.invalidateDetailCache()
    }

    // MARK: - Date formatting

    /// Cached formatter — DateFormatter is expensive to instantiate and was
    /// previously being created for every card on every render.
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()

    private func formatDateShort(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date).uppercased()
    }
}
