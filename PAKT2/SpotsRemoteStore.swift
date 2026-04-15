import Foundation
import Combine
import CoreLocation

/// Thin iOS wrapper around the /v1/spots backend endpoint. Mirrors
/// EventsRemoteStore so the Spots sub-tab of NearYouView gets the same
/// polish (remote data, category filter, search query debounce, empty state).
///
/// Thread safety: @MainActor — all @Published mutations happen on the main
/// actor automatically.
@MainActor
final class SpotsRemoteStore: ObservableObject {
    static let shared = SpotsRemoteStore()

    // MARK: - Published state

    @Published private(set) var spots: [APIClient.APISpot] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    /// Key used to derive a cache entry + dedupe re-fetches.
    private struct FetchKey: Hashable {
        let cityId: String
        let categories: [String]
        let kinds: [String]
        let query: String
        // User location is rounded to 0.005° (~550m) so small moves don't
        // invalidate the cache. At 550m granularity the sort order is stable
        // enough for a filter list.
        let latBucket: Int?
        let lngBucket: Int?
        let maxKm: Double?
    }

    private var lastKey: FetchKey?
    private var lastFetchAt: Date?
    private let cacheTTL: TimeInterval = 120

    private let api = APIClient.shared

    private init() {}

    // MARK: - Load

    /// Fetch spots for the given city + filters. Results replace `spots`.
    /// Skips the network round-trip if the same key was fetched within the TTL.
    func loadSpots(
        cityId: String,
        categories: [String] = [],
        kinds: [String] = [],
        query: String = "",
        userLat: Double? = nil,
        userLng: Double? = nil,
        maxKm: Double? = nil,
        forceRefresh: Bool = false
    ) async {
        let latBucket = userLat.map { Int(($0 * 200.0).rounded()) }
        let lngBucket = userLng.map { Int(($0 * 200.0).rounded()) }
        let key = FetchKey(
            cityId: cityId,
            categories: categories.sorted(),
            kinds: kinds.sorted(),
            query: query,
            latBucket: latBucket,
            lngBucket: lngBucket,
            maxKm: maxKm
        )
        if !forceRefresh,
           let lastKey = lastKey, lastKey == key,
           let lastFetchAt = lastFetchAt, Date().timeIntervalSince(lastFetchAt) < cacheTTL {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.listSpots(
                cityId: cityId,
                categories: categories,
                kinds: kinds,
                query: query.isEmpty ? nil : query,
                userLat: userLat,
                userLng: userLng,
                maxKm: maxKm
            )
            spots = result
            lastKey = key
            lastFetchAt = Date()
            lastError = nil
        } catch {
            lastError = "Failed to load spots: \(error.localizedDescription)"
            Log.d("[SpotsRemoteStore] loadSpots error: \(error)")
        }
    }

    /// Drop the cache so the next loadSpots call performs a fresh fetch.
    func invalidate() {
        lastKey = nil
        lastFetchAt = nil
    }

    // MARK: - Helpers

    /// Compute distance in km from the user location to a spot.
    nonisolated static func distanceKm(spot: APIClient.APISpot, from userLocation: CLLocation) -> Double {
        let loc = CLLocation(latitude: spot.lat, longitude: spot.lng)
        return userLocation.distance(from: loc) / 1000.0
    }
}
