import SwiftUI
import CoreLocation

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

    // UI state
    @State private var activeFilter: FilterChip = .all
    @State private var searchQuery = ""
    @State private var showCityPicker = false
    @State private var showSearchBar = false
    @State private var showCreateSheet = false
    @State private var selectedEvent: APIClient.APIEventListRow? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    enum FilterChip: String, CaseIterable, Identifiable {
        case all, tonight, weekend, week, friends, myEvents
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:      return "All"
            case .tonight:  return "Tonight"
            case .weekend:  return "Weekend"
            case .week:     return "This week"
            case .friends:  return "Friends"
            case .myEvents: return "My events"
            }
        }
        var backendFilter: String? {
            switch self {
            case .all:      return nil
            case .tonight:  return "tonight"
            case .weekend:  return "weekend"
            case .week:     return "week"
            case .friends:  return nil
            case .myEvents: return nil
            }
        }
        var friendsOnly: Bool { self == .friends }
        var isMyEvents: Bool { self == .myEvents }
        var sectionTitle: String {
            switch self {
            case .all:      return "All events"
            case .tonight:  return "Tonight"
            case .weekend:  return "This weekend"
            case .week:     return "This week"
            case .friends:  return "Friends only"
            case .myEvents: return "My events"
            }
        }
    }

    private var selectedCity: APIClient.APICity? {
        guard let id = store.selectedCityId else { return nil }
        return store.cities.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            chips
            content
        }
        .task {
            await bootstrap()
        }
        .onChange(of: store.selectedCityId) { _, _ in
            Task { await reload() }
        }
        .onChange(of: activeFilter) { _, _ in
            Task { await reload() }
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // City picker pill
                Button {
                    showCityPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 15))
                        Text(selectedCity?.name ?? "Select city")
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

                // Search toggle
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
                        .background(
                            Circle().fill(Theme.bgCard)
                        )
                }
                .buttonStyle(.plain)

                // Create event
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, showSearchBar ? 4 : 12)

            // Optional expanded search bar
            if showSearchBar {
                searchBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterChip.allCases) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
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
                Text("Loading events...")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else if activeFilter.isMyEvents {
            myEventsContent
        } else if loaded && heroEvents.isEmpty && friendsEvents.isEmpty && weekEvents.isEmpty {
            emptyState
        } else {
            // No inner ScrollView — EventsFeedView is embedded inside the
            // outer NearYouView ScrollView which handles vertical scrolling.
            // Horizontal scrolls (hero section) are still their own ScrollViews.
            VStack(alignment: .leading, spacing: 28) {
                heroSection
                friendsSection
                weekSection
            }
            .padding(.top, 4)
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
                        myRsvp: detail.myRsvp, friendsGoingCount: detail.friendsGoingCount,
                        friendNames: detail.friendNames
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

    // MARK: - Hero section (XL horizontal scroll)

    @ViewBuilder
    private var heroSection: some View {
        if !heroEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "This weekend in \(selectedCity?.name ?? "Brussels")",
                    subtitle: nil
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(heroEvents.prefix(8)) { row in
                            eventCardXL(row)
                                .onTapGesture { selectedEvent = row }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Friends section (M cards)

    @ViewBuilder
    private var friendsSection: some View {
        if !friendsEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Your friends are going", subtitle: nil)
                VStack(spacing: 10) {
                    ForEach(friendsEvents.prefix(5)) { row in
                        eventCardM(row)
                            .onTapGesture { selectedEvent = row }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Week section

    @ViewBuilder
    private var weekSection: some View {
        if !weekEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: activeFilter.sectionTitle, subtitle: nil)
                VStack(spacing: 10) {
                    ForEach(weekEvents) { row in
                        eventCardM(row)
                            .onTapGesture { selectedEvent = row }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.text)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
            }
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
                        .frame(width: 280, height: 180)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(formatDateShort(row.date))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .tracking(0.5)

                Text(row.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textFaint)
                        Text(row.location)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                }

                friendsGoingBadge(row)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280, height: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.bgCard)
        )
    }

    // MARK: - Event card M (stacked list row)

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

                friendsGoingBadge(row)
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

    private func friendsGoingBadge(_ row: APIClient.APIEventListRow) -> some View {
        let hasFriends = row.friendsGoingCount > 0 && !row.friendNames.isEmpty
        return HStack(spacing: 6) {
            if hasFriends {
                HStack(spacing: -6) {
                    ForEach(Array(row.friendNames.prefix(3).enumerated()), id: \.offset) { _, name in
                        Circle()
                            .fill(Theme.green.opacity(0.2))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Theme.green)
                            )
                            .overlay(
                                Circle().strokeBorder(Theme.bgCard, lineWidth: 1.5)
                            )
                    }
                }
            }
            Text(friendBadgeText(row))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(hasFriends ? Theme.green : Theme.textFaint)
                .lineLimit(1)
        }
    }

    private func friendBadgeText(_ row: APIClient.APIEventListRow) -> String {
        let count = row.friendsGoingCount
        let names = row.friendNames
        if count == 0 {
            return "0 going"
        }
        if names.isEmpty {
            return "\(count) going"
        }
        let joined = names.prefix(3).joined(separator: ", ")
        let extra = count - min(names.count, 3)
        if extra > 0 {
            return "\(joined) +\(extra) going"
        }
        return "\(joined) going"
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

    private func reload() async {
        guard let cityId = store.selectedCityId else { return }
        loading = true
        defer {
            loading = false
            loaded = true
        }

        // My Events chip: different flow — fetch user's own RSVP'd events
        if activeFilter.isMyEvents {
            let uid = AuthManager.shared.currentUser?.id ?? ""
            if !uid.isEmpty {
                myEvents = await EventManager.shared.fetchUserEvents(userId: uid)
            }
            heroEvents = []
            friendsEvents = []
            weekEvents = []
            return
        }

        myEvents = []

        let now = Date()
        let longWindowEnd = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now.addingTimeInterval(90 * 24 * 3600)
        let q = searchQuery.isEmpty ? nil : searchQuery
        let currentFilter = activeFilter

        async let main: [APIClient.APIEventListRow] = {
            if currentFilter == .all {
                return await store.fetchEvents(
                    cityId: cityId,
                    query: q,
                    from: now,
                    to: longWindowEnd,
                    limit: 100
                )
            } else if currentFilter == .friends {
                return await store.fetchEvents(
                    cityId: cityId,
                    query: q,
                    from: now,
                    to: longWindowEnd,
                    friendsOnly: true,
                    limit: 100
                )
            } else {
                return await store.fetchEvents(
                    cityId: cityId,
                    filter: currentFilter.backendFilter,
                    query: q,
                    limit: 100
                )
            }
        }()

        async let hero = store.fetchEvents(
            cityId: cityId,
            filter: "weekend",
            query: q,
            limit: 8
        )

        async let friends = store.fetchEvents(
            cityId: cityId,
            query: q,
            from: now,
            to: longWindowEnd,
            friendsOnly: true,
            limit: 10
        )

        let (mainResult, heroResult, friendsResult) = await (main, hero, friends)
        weekEvents = mainResult
        heroEvents = heroResult
        friendsEvents = friendsResult
    }

    // MARK: - Date formatting

    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE d MMM · HH:mm"
        return formatter.string(from: date).uppercased()
    }
}
