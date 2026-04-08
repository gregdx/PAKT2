import Foundation
// EventbriteAPI class removed — legacy dead code.
// Shared TM model types retained for NearYouView compatibility.

// MARK: - Models (shared)

struct TMEvent: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let url: String
    let locale: String?
    let images: [TMImage]?
    let sales: TMSales?
    let dates: TMDates
    let classifications: [TMClassification]?
    let priceRanges: [TMPriceRange]?
    let _embedded: EventEmbedded?
    let info: String?
    let pleaseNote: String?

    struct EventEmbedded: Codable {
        let venues: [TMVenue]?
        let attractions: [TMAttraction]?
    }

    // Computed properties
    var venue: TMVenue? {
        _embedded?.venues?.first
    }

    var mainImage: TMImage? {
        images?.first { $0.ratio == "16_9" && $0.width >= 1024 } ?? images?.first
    }

    var categoryName: String {
        classifications?.first?.segment?.name ?? "Event"
    }

    var genreName: String? {
        classifications?.first?.genre?.name
    }

    var formattedDate: String {
        guard let localDate = dates.start.localDate else { return "Date TBA" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: localDate) else { return localDate }

        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "fr_FR")

        var result = formatter.string(from: date)

        if let localTime = dates.start.localTime {
            result += " • \(localTime.prefix(5))"
        }

        return result
    }

    var priceRange: String? {
        guard let ranges = priceRanges, let first = ranges.first else { return nil }
        if let min = first.min, let max = first.max, min != max {
            return "\(Int(min))€ - \(Int(max))€"
        } else if let min = first.min {
            return "À partir de \(Int(min))€"
        }
        return nil
    }

    var distance: String? {
        guard let _ = venue,
              let _ = Double(venue?.location?.latitude ?? ""),
              let _ = Double(venue?.location?.longitude ?? "") else {
            return nil
        }
        return nil
    }
}

struct TMImage: Codable {
    let ratio: String?
    let url: String
    let width: Int
    let height: Int
    let fallback: Bool?
}

struct TMSales: Codable {
    let `public`: PublicSale?

    struct PublicSale: Codable {
        let startDateTime: String?
        let endDateTime: String?
    }
}

struct TMDates: Codable {
    let start: DateInfo
    let end: DateInfo?
    let timezone: String?
    let status: Status?

    struct DateInfo: Codable {
        let localDate: String?
        let localTime: String?
        let dateTime: String?
    }

    struct Status: Codable {
        let code: String
    }
}

struct TMClassification: Codable {
    let primary: Bool?
    let segment: Segment?
    let genre: Genre?
    let subGenre: SubGenre?

    struct Segment: Codable {
        let id: String
        let name: String
    }

    struct Genre: Codable {
        let id: String
        let name: String
    }

    struct SubGenre: Codable {
        let id: String
        let name: String
    }
}

struct TMPriceRange: Codable {
    let type: String?
    let currency: String
    let min: Double?
    let max: Double?
}

struct TMVenue: Codable, Identifiable {
    let id: String
    let name: String
    let type: String?
    let url: String?
    let locale: String?
    let postalCode: String?
    let timezone: String?
    let city: City?
    let state: State?
    let country: Country?
    let address: Address?
    let location: Location?
    let images: [TMImage]?

    struct City: Codable {
        let name: String
    }

    struct State: Codable {
        let name: String?
        let stateCode: String?
    }

    struct Country: Codable {
        let name: String
        let countryCode: String
    }

    struct Address: Codable {
        let line1: String?
        let line2: String?
    }

    struct Location: Codable {
        let longitude: String
        let latitude: String
    }

    var fullAddress: String {
        var parts: [String] = []
        if let line1 = address?.line1 { parts.append(line1) }
        if let city = city?.name { parts.append(city) }
        if let postal = postalCode { parts.append(postal) }
        return parts.joined(separator: ", ")
    }
}

struct TMAttraction: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let url: String?
    let locale: String?
    let images: [TMImage]?
    let classifications: [TMClassification]?
}
