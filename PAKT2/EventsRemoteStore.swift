import Foundation
import Combine
import CoreLocation

/// Thin iOS wrapper around the new pakt-api `/v1/events` + `/v1/cities` endpoints
/// introduced in Step 1 of the events social redesign. This replaces direct
/// RA GraphQL fetching from NearYouView — all event data now transits through
/// the backend which handles RA ingest, caching, visibility, and friend overlay.
///
/// Usage:
///   @StateObject private var store = EventsRemoteStore.shared
///   .task { await store.loadFeed(cityId: store.selectedCityId ?? "city_brussels", filter: "week") }
///
/// Thread safety: all @Published mutations happen on the MainActor via the
/// @MainActor class-level annotation.
@MainActor
final class EventsRemoteStore: ObservableObject {
    static let shared = EventsRemoteStore()

    // MARK: - Published state

    @Published private(set) var cities: [APIClient.APICity] = []
    @Published private(set) var feed: [APIClient.APIEventListRow] = []
    @Published private(set) var isLoadingCities: Bool = false
    @Published private(set) var isLoadingFeed: Bool = false
    @Published private(set) var lastError: String?

    /// Currently selected city id. Persisted in UserDefaults so it survives restarts.
    @Published var selectedCityId: String? {
        didSet {
            if let id = selectedCityId {
                UserDefaults.standard.set(id, forKey: Self.selectedCityIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedCityIdKey)
            }
        }
    }

    private static let selectedCityIdKey = "pakt_events_selected_city_id"

    // MARK: - In-memory detail cache

    private var detailCache: [String: (detail: APIClient.APIEventDetail, cachedAt: Date)] = [:]
    private let detailCacheTTL: TimeInterval = 300 // 5 minutes

    private let api = APIClient.shared

    private init() {
        self.selectedCityId = UserDefaults.standard.string(forKey: Self.selectedCityIdKey)
    }

    // MARK: - Cities

    func loadCities() async {
        isLoadingCities = true
        defer { isLoadingCities = false }
        do {
            cities = try await api.listCities()
        } catch {
            lastError = "Failed to load cities: \(error.localizedDescription)"
            Log.d("[EventsRemoteStore] loadCities error: \(error)")
        }
    }

    /// Ask the backend for the closest supported city given the user's coordinates.
    /// Updates `selectedCityId` on success.
    func suggestCity(for coordinate: CLLocationCoordinate2D) async {
        do {
            let city = try await api.getNearestCity(lat: coordinate.latitude, lng: coordinate.longitude)
            if selectedCityId == nil {
                selectedCityId = city.id
            }
        } catch {
            Log.d("[EventsRemoteStore] suggestCity error: \(error)")
        }
    }

    // MARK: - Feed

    /// Load the event feed for a city. `filter` matches the backend presets:
    /// "tonight", "weekend", "week", "friends_only", or nil for the default 7-day window.
    func loadFeed(
        cityId: String,
        filter: String? = "week",
        query: String? = nil,
        friendsOnly: Bool = false
    ) async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            feed = try await api.listEvents(
                cityId: cityId,
                filter: filter,
                query: query,
                friendsOnly: friendsOnly
            )
        } catch {
            lastError = "Failed to load events: \(error.localizedDescription)"
            Log.d("[EventsRemoteStore] loadFeed error: \(error)")
        }
    }

    // MARK: - Detail (cached)

    /// Fetch a single event detail. Cached for `detailCacheTTL` seconds.
    /// Used by EventDetailSheet + EventMessageCard (chat event share).
    func fetchDetail(id: String, forceRefresh: Bool = false) async -> APIClient.APIEventDetail? {
        if !forceRefresh,
           let cached = detailCache[id],
           Date().timeIntervalSince(cached.cachedAt) < detailCacheTTL {
            return cached.detail
        }
        do {
            let detail = try await api.getEvent(id: id)
            detailCache[id] = (detail, Date())
            return detail
        } catch {
            Log.d("[EventsRemoteStore] fetchDetail \(id) error: \(error)")
            return nil
        }
    }

    func invalidateDetailCache(id: String? = nil) {
        if let id = id {
            detailCache.removeValue(forKey: id)
        } else {
            detailCache.removeAll()
        }
    }

    // MARK: - Non-caching fetch for multi-section views

    /// Returns a list of events without touching published state or cache. Callers
    /// manage their own local @State arrays. Used by EventsFeedView which needs
    /// multiple independent slices (hero weekend, friends, week) simultaneously.
    func fetchEvents(
        cityId: String,
        filter: String? = nil,
        query: String? = nil,
        source: String? = nil,
        from: Date? = nil,
        to: Date? = nil,
        friendsOnly: Bool = false,
        limit: Int = 30
    ) async -> [APIClient.APIEventListRow] {
        do {
            return try await api.listEvents(
                cityId: cityId,
                filter: filter,
                query: query,
                source: source,
                from: from,
                to: to,
                friendsOnly: friendsOnly,
                limit: limit
            )
        } catch {
            Log.d("[EventsRemoteStore] fetchEvents(\(cityId), \(filter ?? "-")) error: \(error)")
            return []
        }
    }

    // MARK: - RSVP

    /// Set RSVP status on an event. Uses the legacy POST /events/attend endpoint
    /// which takes the full event payload. Returns true on success.
    @discardableResult
    func setRSVP(
        row: APIClient.APIEventListRow,
        status: String
    ) async -> Bool {
        let iso = ISO8601DateFormatter()
        let dateStr = iso.string(from: row.date)
        let endDateStr = row.endDate.map { iso.string(from: $0) } ?? ""
        let req = APIClient.AttendRequest(
            eventId: row.id,
            status: status,
            title: row.title,
            description: row.description,
            date: dateStr,
            endDate: endDateStr,
            location: row.location,
            address: row.address,
            source: row.source,
            sourceUrl: row.sourceUrl,
            imageUrl: row.imageUrl
        )
        do {
            try await api.setEventAttendance(req)
            invalidateDetailCache(id: row.id)
            return true
        } catch {
            Log.d("[EventsRemoteStore] setRSVP \(row.id) error: \(error)")
            return false
        }
    }

    @discardableResult
    func removeRSVP(eventId: String) async -> Bool {
        do {
            try await api.removeEventAttendance(eventId: eventId)
            invalidateDetailCache(id: eventId)
            return true
        } catch {
            Log.d("[EventsRemoteStore] removeRSVP \(eventId) error: \(error)")
            return false
        }
    }

    // MARK: - User event creation

    enum CreateEventError: Error {
        case missingTitle
        case missingCity
        case apiError(String)
    }

    func createEvent(
        title: String,
        description: String,
        date: Date,
        endDate: Date?,
        location: String,
        address: String,
        visibility: String,
        invitedUserIds: [String],
        imageUrl: String = ""
    ) async throws -> APIClient.APIEventDetail {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CreateEventError.missingTitle
        }
        guard let cityId = selectedCityId else {
            throw CreateEventError.missingCity
        }

        let iso = ISO8601DateFormatter()
        let body = APIClient.CreateEventBody(
            title: title,
            description: description,
            date: iso.string(from: date),
            endDate: endDate.map { iso.string(from: $0) } ?? "",
            location: location,
            address: address,
            cityId: cityId,
            venueLat: nil,
            venueLng: nil,
            imageUrl: imageUrl,
            visibility: visibility,
            invitedUserIds: invitedUserIds
        )
        do {
            let detail = try await api.createEvent(body)
            return detail
        } catch {
            Log.d("[EventsRemoteStore] createEvent error: \(error)")
            throw CreateEventError.apiError(error.localizedDescription)
        }
    }

    func deleteEvent(id: String) async -> Bool {
        do {
            try await api.deleteEvent(id: id)
            invalidateDetailCache(id: id)
            return true
        } catch {
            Log.d("[EventsRemoteStore] deleteEvent error: \(error)")
            return false
        }
    }
}
