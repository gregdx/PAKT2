import Foundation

// MARK: - Ticketmaster Discovery API Client
// Free tier: 5000 requests/day
// Docs: https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/

final class TicketmasterService {
    static let shared = TicketmasterService()

    // Get your key at https://developer.ticketmaster.com/
    private let apiKey = "YOUR_TM_API_KEY" // TODO: Replace with real key
    private let baseURL = "https://app.ticketmaster.com/discovery/v2"

    private init() {}

    var isConfigured: Bool { apiKey != "YOUR_TM_API_KEY" && !apiKey.isEmpty }

    /// Fetch real events near a location using Ticketmaster Discovery API.
    /// Returns TMEvent objects compatible with EventDetailSheet.
    func fetchNearbyEvents(
        lat: Double,
        lon: Double,
        radiusKm: Int = 50,
        size: Int = 20
    ) async throws -> [TMEvent] {
        guard isConfigured else {
            Log.d("[TM] API key not configured, skipping")
            return []
        }
        var components = URLComponents(string: "\(baseURL)/events.json")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "latlong", value: "\(lat),\(lon)"),
            URLQueryItem(name: "radius", value: "\(radiusKm)"),
            URLQueryItem(name: "unit", value: "km"),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "sort", value: "date,asc"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            Log.e("[TM] HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "?")")
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let result: TMSearchResponse
        do {
            result = try decoder.decode(TMSearchResponse.self, from: data)
        } catch {
            Log.e("[TM] Decode error: \(error)")
            throw error
        }
        return result._embedded?.events ?? []
    }
}

// MARK: - API Response wrapper

/// Top-level response from Ticketmaster Discovery API /events.json
struct TMSearchResponse: Codable {
    let _embedded: TMSearchEmbedded?
    let page: TMPage?
}

struct TMSearchEmbedded: Codable {
    let events: [TMEvent]?
}

struct TMPage: Codable {
    let size: Int?
    let totalElements: Int?
    let totalPages: Int?
    let number: Int?
}
