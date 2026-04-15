import SwiftUI
import Combine
import EventKit

// MARK: - PaktEvent model

struct PaktEvent: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var description: String = ""
    var date: Date
    var endDate: Date? = nil
    var location: String = ""
    var address: String = ""
    var creatorId: String
    var creatorName: String
    var imageData: Data? = nil
    var isPublic: Bool = true
    var source: String = "pakt"
    var sourceUrl: String = ""
    var imageUrl: String = ""

    var goingIds: [String] = []
    var interestedIds: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, title, description, date, endDate, location, address, creatorId, creatorName, isPublic, goingIds, interestedIds, source, sourceUrl, imageUrl
        // imageData excluded — stored as file
    }

    var goingCount: Int { goingIds.count }
    var interestedCount: Int { interestedIds.count }

    var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: date)
    }

    var isPast: Bool { date < Date() }

    var mapsURL: URL? {
        guard !address.isEmpty else { return nil }
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }

    var image: UIImage? {
        if let data = imageData { return UIImage(data: data) }
        if let data = EventManager.loadImage(for: id) { return UIImage(data: data) }
        return nil
    }
}

// MARK: - EventManager

final class EventManager: ObservableObject {
    static let shared = EventManager()

    @Published var events: [PaktEvent] = []
    private let storageKey = "pakt_events"

    private static var imageDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("event_images")
    }

    static func saveImage(_ data: Data, for eventId: String) {
        let dir = imageDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("\(eventId).jpg"))
    }

    static func loadImage(for eventId: String) -> Data? {
        try? Data(contentsOf: imageDir.appendingPathComponent("\(eventId).jpg"))
    }

    static func deleteImage(for eventId: String) {
        try? FileManager.default.removeItem(at: imageDir.appendingPathComponent("\(eventId).jpg"))
    }

    init() { loadLocal() }

    // MARK: - CRUD

    func createEvent(_ event: PaktEvent) {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        if let imgData = event.imageData {
            EventManager.saveImage(imgData, for: event.id)
        }
        events.insert(event, at: 0)
        saveLocal()
    }

    func updateEvent(_ event: PaktEvent) {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        if let imgData = event.imageData {
            EventManager.saveImage(imgData, for: event.id)
        }
        events[i] = event
        saveLocal()
    }

    func deleteEvent(_ eventId: String) {
        EventManager.deleteImage(for: eventId)
        events.removeAll { $0.id == eventId }
        saveLocal()
    }

    // MARK: - Going / Interested (local + API sync)

    private var pendingTasks: [String: Task<Void, Never>] = [:]

    func toggleGoing(eventId: String, userId: String) {
        guard let i = events.firstIndex(where: { $0.id == eventId }) else { return }
        let wasGoing = events[i].goingIds.contains(userId)

        if wasGoing {
            events[i].goingIds.removeAll { $0 == userId }
        } else {
            events[i].goingIds.append(userId)
            events[i].interestedIds.removeAll { $0 == userId }
        }
        saveLocal()

        let currentUID = AppState.shared.currentUID
        guard userId == currentUID else { return }
        let event = events[i]

        pendingTasks[eventId]?.cancel()
        pendingTasks[eventId] = Task {
            do {
                if wasGoing {
                    try await APIClient.shared.removeEventAttendance(eventId: eventId)
                } else {
                    try await APIClient.shared.setEventAttendance(buildAttendRequest(event: event, status: "going"))
                }
            } catch {
                if !Task.isCancelled { Log.e("[EventManager] Sync going failed: \(error)") }
            }
            pendingTasks[eventId] = nil
        }
    }

    func toggleInterested(eventId: String, userId: String) {
        guard let i = events.firstIndex(where: { $0.id == eventId }) else { return }
        let wasInterested = events[i].interestedIds.contains(userId)

        if wasInterested {
            events[i].interestedIds.removeAll { $0 == userId }
        } else {
            events[i].interestedIds.append(userId)
            events[i].goingIds.removeAll { $0 == userId }
        }
        saveLocal()

        let currentUID = AppState.shared.currentUID
        guard userId == currentUID else { return }
        let event = events[i]

        pendingTasks[eventId]?.cancel()
        pendingTasks[eventId] = Task {
            do {
                if wasInterested {
                    try await APIClient.shared.removeEventAttendance(eventId: eventId)
                } else {
                    try await APIClient.shared.setEventAttendance(buildAttendRequest(event: event, status: "interested"))
                }
            } catch {
                if !Task.isCancelled { Log.e("[EventManager] Sync interested failed: \(error)") }
            }
            pendingTasks[eventId] = nil
        }
    }

    private func buildAttendRequest(event: PaktEvent, status: String) -> APIClient.AttendRequest {
        let isoFormatter = ISO8601DateFormatter()
        return APIClient.AttendRequest(
            eventId: event.id,
            status: status,
            title: event.title,
            description: event.description,
            date: isoFormatter.string(from: event.date),
            endDate: event.endDate.map { isoFormatter.string(from: $0) } ?? "",
            location: event.location,
            address: event.address,
            source: event.source,
            sourceUrl: event.sourceUrl,
            imageUrl: event.imageUrl
        )
    }

    // MARK: - Ensure RA Event exists locally

    func ensureRAEvent(raEvent: RAEvent) -> String {
        let paktId = "ra_\(raEvent.id)"
        if events.contains(where: { $0.id == paktId }) { return paktId }

        var eventDate = Date()
        var eventEndDate: Date? = nil
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        if let st = raEvent.startTime, let d = f.date(from: st) { eventDate = d }
        if let et = raEvent.endTime, let d = f.date(from: et) { eventEndDate = d }

        let paktEvent = PaktEvent(
            id: paktId,
            title: raEvent.title,
            description: raEvent.artistNames ?? "",
            date: eventDate,
            endDate: eventEndDate,
            location: raEvent.venueName ?? "",
            address: raEvent.venueAddress ?? "",
            creatorId: "ra",
            creatorName: "Resident Advisor",
            isPublic: true,
            source: "ra",
            sourceUrl: raEvent.eventURL,
            imageUrl: raEvent.flyerFront ?? ""
        )
        createEvent(paktEvent)
        return paktId
    }

    // MARK: - Fetch friend's events from API

    func fetchUserEvents(userId: String) async -> [APIClient.APIUserEvent] {
        do {
            let results = try await APIClient.shared.getUserEvents(userId: userId)
            Log.d("[EventManager] fetchUserEvents(\(userId)): \(results.count) events")
            return results
        } catch {
            Log.e("[EventManager] fetchUserEvents(\(userId)) FAILED: \(error)")
            return []
        }
    }

    // MARK: - Queries

    func upcomingEvents() -> [PaktEvent] {
        let uid = AppState.shared.currentUID
        return events.filter { event in
            !event.isPast
            && (event.source != "ra"
                || event.goingIds.contains(uid)
                || event.interestedIds.contains(uid))
        }
        .sorted { $0.date < $1.date }
    }

    func eventsForUser(_ userId: String) -> [PaktEvent] {
        events.filter {
            !$0.isPast
            && ($0.goingIds.contains(userId) || $0.interestedIds.contains(userId))
        }
        .sorted { $0.date < $1.date }
    }

    func friendNames(for ids: [String], friendManager: FriendManager) -> [String] {
        ids.compactMap { uid in
            friendManager.friends.first(where: { $0.id == uid })?.firstName
        }
    }

    // MARK: - Apple Calendar

    static func addToCalendar(event: PaktEvent, completion: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, _ in
            guard granted else { DispatchQueue.main.async { completion(false) }; return }
            let ekEvent = EKEvent(eventStore: store)
            ekEvent.title = event.title
            ekEvent.startDate = event.date
            ekEvent.endDate = event.endDate ?? event.date.addingTimeInterval(7200)
            ekEvent.notes = event.description
            if !event.address.isEmpty { ekEvent.location = event.address }
            ekEvent.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(ekEvent, span: .thisEvent)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Persistence

    private func saveLocal() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(events) else {
            Log.e("[EventManager] Failed to encode events")
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let decoded = try? decoder.decode([PaktEvent].self, from: data) else {
            Log.e("[EventManager] Failed to decode events")
            return
        }
        events = decoded
    }
}
