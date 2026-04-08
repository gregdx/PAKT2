import Foundation
import CoreLocation

// MARK: - Foursquare Places API v3
// Docs: https://docs.foursquare.com/developer/reference/place-search
// Free tier: up to 50 calls/day
// Get your API key at https://foursquare.com/developers

final class FoursquareService {
    static let shared = FoursquareService()

    // TODO: Replace with your Foursquare API key
    private let apiKey = "YOUR_FSQ_KEY"
    private let baseURL = "https://api.foursquare.com/v3"

    var isConfigured: Bool { apiKey != "YOUR_FSQ_KEY" && !apiKey.isEmpty }

    /// Search for nearby places using Foursquare Places API v3
    func searchNearby(
        lat: Double,
        lon: Double,
        radiusMeters: Int = 15000,
        categories: String? = nil,
        limit: Int = 30
    ) async throws -> [DiscoverSpot] {
        guard isConfigured else {
            Log.d("[FSQ] API key not configured, skipping")
            return []
        }
        var components = URLComponents(string: "\(baseURL)/places/search")!
        var queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
            URLQueryItem(name: "radius", value: "\(radiusMeters)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "DISTANCE"),
            URLQueryItem(name: "fields", value: "fsq_id,name,categories,distance,geocodes,location,rating,photos,website,tel")
        ]
        if let cats = categories {
            queryItems.append(URLQueryItem(name: "categories", value: cats))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            Log.e("[FSQ] HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "?")")
            throw URLError(.badServerResponse)
        }

        let result: FSQResponse
        do {
            result = try JSONDecoder().decode(FSQResponse.self, from: data)
        } catch {
            Log.e("[FSQ] Decode error: \(error)")
            throw error
        }
        return result.results.map { $0.toDiscoverSpot() }
    }
}

// MARK: - Foursquare API Response Models

struct FSQResponse: Codable {
    let results: [FSQPlace]
}

struct FSQPlace: Codable {
    let fsq_id: String
    let name: String
    let categories: [FSQCategory]?
    let distance: Int?
    let geocodes: FSQGeocodes?
    let location: FSQLocation?
    let rating: Double?
    let photos: [FSQPhoto]?
    let website: String?
    let tel: String?

    struct FSQCategory: Codable {
        let id: Int
        let name: String
        let icon: FSQIcon?

        struct FSQIcon: Codable {
            let prefix: String
            let suffix: String
        }
    }

    struct FSQGeocodes: Codable {
        let main: FSQLatLng?

        struct FSQLatLng: Codable {
            let latitude: Double
            let longitude: Double
        }
    }

    struct FSQLocation: Codable {
        let address: String?
        let formatted_address: String?
        let locality: String?
        let region: String?
    }

    struct FSQPhoto: Codable {
        let prefix: String
        let suffix: String
        let width: Int?
        let height: Int?

        var url: String { "\(prefix)original\(suffix)" }
    }

    func toDiscoverSpot() -> DiscoverSpot {
        let cat = categories?.first
        let photo = photos?.first
        return DiscoverSpot(
            id: fsq_id,
            name: name,
            category: cat?.name ?? "Place",
            distance: Double(distance ?? 0) / 1000.0,
            latitude: geocodes?.main?.latitude ?? 0,
            longitude: geocodes?.main?.longitude ?? 0,
            address: location?.formatted_address ?? location?.address ?? "",
            rating: rating,
            photoURL: photo?.url,
            website: website
        )
    }
}

// MARK: - DiscoverSpot (unified model for API spots)

struct DiscoverSpot: Identifiable {
    let id: String
    let name: String
    let category: String       // Foursquare category name (e.g. "Gym / Fitness Center", "Coffee Shop")
    let distance: Double       // km
    let latitude: Double
    let longitude: Double
    let address: String
    let rating: Double?
    let photoURL: String?
    let website: String?

    /// Map Foursquare category names to the app's VenueCategory for filtering
    var venueCategory: VenueCategory? {
        let lower = category.lowercased()
        // Fitness
        if lower.contains("gym") || lower.contains("fitness") || lower.contains("crossfit")
            || lower.contains("pilates") || lower.contains("yoga") || lower.contains("cycling") {
            return .fitness
        }
        // Cafe
        if lower.contains("coffee") || lower.contains("café") || lower.contains("cafe")
            || lower.contains("tea") || lower.contains("bakery") || lower.contains("brunch") {
            return .cafe
        }
        // Outdoor
        if lower.contains("park") || lower.contains("garden") || lower.contains("trail")
            || lower.contains("forest") || lower.contains("lake") || lower.contains("beach")
            || lower.contains("nature") || lower.contains("hiking") {
            return .outdoor
        }
        // Wellness
        if lower.contains("spa") || lower.contains("wellness") || lower.contains("massage")
            || lower.contains("sauna") || lower.contains("pool") || lower.contains("bath") {
            return .wellness
        }
        // Sport
        if lower.contains("sport") || lower.contains("tennis") || lower.contains("padel")
            || lower.contains("basketball") || lower.contains("soccer") || lower.contains("football")
            || lower.contains("climbing") || lower.contains("swim") || lower.contains("stadium")
            || lower.contains("court") || lower.contains("bowling") {
            return .sport
        }
        return nil
    }
}
