import Foundation
import CoreLocation

// MARK: - Brussels Event unified model

struct BrusselsEvent: Identifiable {
    let id: String
    let name: String
    let nameFR: String?
    let nameNL: String?
    let category: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distance: Double // km from user
    let imageURL: String?
    let website: String?
    let description: String?

    var displayName: String {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        if lang == "fr", let fr = nameFR, !fr.isEmpty { return fr }
        return name
    }

    var mapsURL: URL? {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }
}

// MARK: - Brussels Events Service

final class BrusselsEventsService {
    static let shared = BrusselsEventsService()

    // agenda.brussels API token (get at api.brussels/store)
    private let agendaToken = "YOUR_AGENDA_BRUSSELS_TOKEN" // TODO: Replace with real token

    var isConfigured: Bool { agendaToken != "YOUR_AGENDA_BRUSSELS_TOKEN" && !agendaToken.isEmpty }

    private init() {}

    /// Fetch events from agenda.brussels.
    /// If token not configured, falls back to Brussels Open Data venues (free, no auth).
    func fetchEvents(lat: Double, lon: Double, radiusKm: Int = 20) async throws -> [BrusselsEvent] {
        if isConfigured {
            return try await fetchFromAgenda(lat: lat, lon: lon, radiusKm: radiusKm)
        } else {
            return try await fetchFromOpenData(lat: lat, lon: lon, radiusKm: radiusKm)
        }
    }

    // MARK: - agenda.brussels API

    private func fetchFromAgenda(lat: Double, lon: Double, radiusKm: Int) async throws -> [BrusselsEvent] {
        var components = URLComponents(string: "https://api.brussels/api/agenda/0.0.1/events")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "lon", value: "\(lon)"),
            URLQueryItem(name: "radius", value: "\(radiusKm)"),
            URLQueryItem(name: "limit", value: "30"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(agendaToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            Log.e("[Brussels] Agenda API failed, falling back to Open Data")
            return try await fetchFromOpenData(lat: lat, lon: lon, radiusKm: radiusKm)
        }

        do {
            let result = try JSONDecoder().decode(AgendaResponse.self, from: data)
            return result.events.map { $0.toBrusselsEvent() }
        } catch {
            Log.e("[Brussels] Decode error: \(error)")
            return try await fetchFromOpenData(lat: lat, lon: lon, radiusKm: radiusKm)
        }
    }

    // MARK: - Brussels Open Data (free, no auth)

    private func fetchFromOpenData(lat: Double, lon: Double, radiusKm: Int) async throws -> [BrusselsEvent] {
        let datasetId = "lieux_culturels_touristiques_evenementiels_visitbrussels_vbx"
        var components = URLComponents(string: "https://opendata.brussels.be/api/explore/v2.1/catalog/datasets/\(datasetId)/records")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "where", value: "within_distance(geo_point, geom'POINT(\(lon) \(lat))', \(radiusKm)km)"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            Log.e("[Brussels OpenData] HTTP error")
            return []
        }

        do {
            let result = try JSONDecoder().decode(OpenDataResponse.self, from: data)
            let userLocation = CLLocation(latitude: lat, longitude: lon)
            return result.results.compactMap { record in
                record.toBrusselsEvent(userLocation: userLocation)
            }
        } catch {
            Log.e("[Brussels OpenData] Decode error: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                Log.d("[Brussels OpenData] Response: \(str.prefix(500))")
            }
            return []
        }
    }
}

// MARK: - agenda.brussels response models

struct AgendaResponse: Codable {
    let events: [AgendaEvent]
}

struct AgendaEvent: Codable {
    let id: String?
    let title: String?
    let title_fr: String?
    let title_nl: String?
    let category: String?
    let address: String?
    let lat: Double?
    let lon: Double?
    let image: String?
    let url: String?
    let description: String?

    func toBrusselsEvent() -> BrusselsEvent {
        BrusselsEvent(
            id: id ?? UUID().uuidString,
            name: title ?? "Event",
            nameFR: title_fr,
            nameNL: title_nl,
            category: category ?? "Event",
            address: address ?? "",
            latitude: lat ?? 0,
            longitude: lon ?? 0,
            distance: 0,
            imageURL: image,
            website: url,
            description: description
        )
    }
}

// MARK: - Brussels Open Data response models

struct OpenDataResponse: Codable {
    let results: [OpenDataRecord]
}

struct OpenDataRecord: Codable {
    let nom_indicateur_fr: String?
    let nom_indicateur_nl: String?
    let nom_indicateur_en: String?
    let categorie_fr: String?
    let categorie_en: String?
    let adresse_fr: String?
    let code_postal: String?
    let commune_fr: String?
    let geo_point: GeoPoint?
    let url_website: String?
    let url_image: String?
    let description_fr: String?

    struct GeoPoint: Codable {
        let lat: Double?
        let lon: Double?
    }

    func toBrusselsEvent(userLocation: CLLocation) -> BrusselsEvent? {
        guard let lat = geo_point?.lat, let lon = geo_point?.lon else { return nil }
        let name = nom_indicateur_en ?? nom_indicateur_fr ?? "Place"
        let dist = userLocation.distance(from: CLLocation(latitude: lat, longitude: lon)) / 1000.0

        return BrusselsEvent(
            id: "\(name)-\(lat)-\(lon)",
            name: name,
            nameFR: nom_indicateur_fr,
            nameNL: nom_indicateur_nl,
            category: categorie_en ?? categorie_fr ?? "Culture",
            address: [adresse_fr, code_postal, commune_fr].compactMap { $0 }.joined(separator: ", "),
            latitude: lat,
            longitude: lon,
            distance: dist,
            imageURL: url_image,
            website: url_website,
            description: description_fr
        )
    }
}
