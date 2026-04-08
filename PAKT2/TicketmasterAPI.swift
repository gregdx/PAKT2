import Foundation
import CoreLocation

// MARK: - Ticketmaster Event Model

struct TMEvent: Identifiable, Codable {
    let id: String
    let name: String
    let url: String
    let images: [TMImage]?
    let dates: TMDates?
    let classifications: [TMClassification]?
    let priceRanges: [TMPriceRange]?
    let info: String?
    let pleaseNote: String?
    let _embedded: TMEmbedded?
    
    var mainImage: TMImage? {
        images?.first(where: { $0.width ?? 0 > 1000 }) ?? images?.first
    }
    
    var categoryName: String {
        classifications?.first?.segment?.name ?? "Event"
    }
    
    var formattedDate: String {
        guard let start = dates?.start else { return "Date TBA" }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        
        if let dateStr = start.localDate {
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) {
                formatter.dateFormat = "EEEE d MMMM yyyy"
                var result = formatter.string(from: date).capitalized
                
                if let time = start.localTime {
                    result += " • \(time)"
                }
                return result
            }
        }
        
        if let dateTime = start.dateTime {
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if let date = formatter.date(from: dateTime) {
                formatter.dateFormat = "EEEE d MMMM yyyy • HH:mm"
                return formatter.string(from: date).capitalized
            }
        }
        
        return "Date TBA"
    }
    
    var priceRange: String? {
        guard let ranges = priceRanges, !ranges.isEmpty else { return nil }
        
        if ranges.count == 1, let price = ranges.first {
            if let min = price.min, let max = price.max, min == max {
                return "\(Int(min))€"
            }
        }
        
        let prices = ranges.compactMap { $0.min }
        let min = prices.min()
        let max = prices.max()
        
        if let min = min, let max = max {
            if min == max {
                return "\(Int(min))€"
            }
            return "\(Int(min))€ - \(Int(max))€"
        }
        
        return nil
    }
    
    var venue: TMVenue? {
        _embedded?.venues?.first
    }
}

struct TMImage: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

struct TMDates: Codable {
    let start: TMDateStart?
}

struct TMDateStart: Codable {
    let localDate: String?
    let localTime: String?
    let dateTime: String?
}

struct TMClassification: Codable {
    let segment: TMSegment?
}

struct TMSegment: Codable {
    let name: String?
}

struct TMPriceRange: Codable {
    let min: Double?
    let max: Double?
    let currency: String?
}

struct TMEmbedded: Codable {
    let venues: [TMVenue]?
}

struct TMVenue: Codable {
    let name: String
    let city: TMCity?
    let address: TMAddress?
    
    var fullAddress: String {
        var parts: [String] = []
        if let line1 = address?.line1 {
            parts.append(line1)
        }
        if let cityName = city?.name {
            parts.append(cityName)
        }
        return parts.joined(separator: ", ")
    }
}

struct TMCity: Codable {
    let name: String?
}

struct TMAddress: Codable {
    let line1: String?
}

// MARK: - API Response

struct TMResponse: Codable {
    let _embedded: TMResponseEmbedded?
}

struct TMResponseEmbedded: Codable {
    let events: [TMEvent]?
}

// MARK: - Ticketmaster API

class TicketmasterAPI {
    static let shared = TicketmasterAPI()
    
    private let apiKey = "OPD6VMXNOSY46BVZ5E"
    private let baseURL = "https://app.ticketmaster.com/discovery/v2"
    
    private init() {}
    
    func fetchNearbyEvents(
        lat: Double,
        lon: Double,
        radius: Int,
        size: Int = 50
    ) async throws -> [TMEvent] {
        // Construct URL
        let geoPoint = "\(lat),\(lon)"
        let urlString = "\(baseURL)/events.json?apikey=\(apiKey)&latlong=\(geoPoint)&radius=\(radius)&unit=km&size=\(size)&locale=*"
        
        guard let url = URL(string: urlString) else {
            throw TMError.invalidURL
        }
        
        Log.d("[Ticketmaster] Fetching: \(urlString)")
        
        // Fetch data
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMError.invalidResponse
        }
        
        Log.d("[Ticketmaster] HTTP Status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                Log.e("[Ticketmaster] Error response: \(errorString)")
            }
            throw TMError.httpError(httpResponse.statusCode)
        }
        
        // Decode
        let decoder = JSONDecoder()
        let tmResponse = try decoder.decode(TMResponse.self, from: data)
        
        return tmResponse._embedded?.events ?? []
    }
}

// MARK: - Error

enum TMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
