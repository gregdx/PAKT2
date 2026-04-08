import Foundation

// MARK: - Resident Advisor GraphQL API
// Undocumented public API — no auth required
// Brussels area code = 62

final class ResidentAdvisorService {
    static let shared = ResidentAdvisorService()

    private let endpoint = "https://ra.co/graphql"
    private let brusselsAreaCode = 62

    private init() {}

    /// Fetch upcoming events in Brussels for the next `days` days
    func fetchEvents(days: Int = 7, page: Int = 1, pageSize: Int = 20) async throws -> [RAEvent] {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let endDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(days * 86400))).prefix(10)

        let query = """
        query GET_DEFAULT_EVENTS_LISTING($filters: FilterInputDtoInput, $pageSize: Int, $page: Int) {
          eventListings(filters: $filters, pageSize: $pageSize, page: $page) {
            data {
              id
              event {
                id
                title
                date
                startTime
                endTime
                contentUrl
                flyerFront
                venue {
                  name
                  address
                  area { name }
                }
                artists { name }
              }
            }
            totalResults
          }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": [
                "filters": [
                    "areas": ["eq": brusselsAreaCode],
                    "listingDate": [
                        "gte": String(today),
                        "lte": String(endDate)
                    ]
                ],
                "pageSize": pageSize,
                "page": page
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://ra.co/events/be/brussels", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            Log.e("[RA] HTTP error")
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(RAGraphQLResponse.self, from: data)
        return result.data.eventListings.data.compactMap { $0.event }
    }
}

// MARK: - GraphQL Response Models

struct RAGraphQLResponse: Codable {
    let data: RAData

    struct RAData: Codable {
        let eventListings: RAEventListings
    }

    struct RAEventListings: Codable {
        let data: [RAEventListing]
        let totalResults: Int
    }

    struct RAEventListing: Codable {
        let id: String
        let event: RAEvent?
    }
}

// MARK: - RAEvent

struct RAEvent: Identifiable, Codable {
    let id: String
    let title: String
    let date: String?
    let startTime: String?
    let endTime: String?
    let contentUrl: String?
    let flyerFront: String?
    let venue: RAVenue?
    let artists: [RAArtist]?

    var eventURL: String {
        "https://ra.co\(contentUrl ?? "")"
    }

    var imageURL: String? {
        flyerFront
    }

    var formattedDate: String {
        guard let startTime = startTime else { return date?.prefix(10).description ?? "Date TBA" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard let parsed = formatter.date(from: startTime) else {
            return date?.prefix(10).description ?? "Date TBA"
        }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        display.locale = Locale(identifier: "fr_FR")
        var result = display.string(from: parsed)

        // Add time
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let start = timeFormatter.date(from: startTime) {
            let tf = DateFormatter()
            tf.dateFormat = "HH:mm"
            result += " \u{2022} \(tf.string(from: start))"
        }

        return result
    }

    var artistNames: String? {
        guard let artists = artists, !artists.isEmpty else { return nil }
        return artists.map { $0.name }.joined(separator: ", ")
    }

    var venueName: String? {
        venue?.name
    }

    var venueAddress: String? {
        venue?.address
    }

    var venueCity: String? {
        venue?.area?.name
    }
}

struct RAVenue: Codable {
    let name: String
    let address: String?
    let area: RAArea?

    struct RAArea: Codable {
        let name: String
    }
}

struct RAArtist: Codable {
    let name: String
}
