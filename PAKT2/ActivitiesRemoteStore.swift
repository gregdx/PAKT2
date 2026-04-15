import Foundation
import Combine

/// Duration bucket used by the "Free activities" filter UI. Maps to a range
/// over `APIActivity.durationMinutes` at display time — we do not yet push
/// the range down to the backend because the dataset is small (~30 rows).
enum ActivityDuration: String, CaseIterable, Identifiable, Codable, Hashable {
    case short   // < 30 min
    case medium  // 30–90 min
    case long    // > 90 min

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short:  return L10n.t("dur_short")
        case .medium: return L10n.t("dur_medium")
        case .long:   return L10n.t("dur_long")
        }
    }

    func matches(_ minutes: Int?) -> Bool {
        guard let m = minutes else { return false }
        switch self {
        case .short:  return m < 30
        case .medium: return m >= 30 && m <= 90
        case .long:   return m > 90
        }
    }
}

/// Persisted user-selected advanced filters for the Free section. Extends
/// naturally to Events (see `AdvancedFiltersSheet`). Stored under
/// `pakt_free_filters` in UserDefaults so selections survive restarts.
struct FreeFilterSelection: Codable, Equatable {
    var categories: Set<String> = []      // ActCategory raw values
    var durations: Set<ActivityDuration> = []
    var featuredOnly: Bool = false
    var searchText: String = ""

    var isEmpty: Bool {
        categories.isEmpty && durations.isEmpty && !featuredOnly && searchText.isEmpty
    }

    /// Count of non-search active filters — used to badge the "Filters" button.
    var activeCount: Int {
        var n = categories.count + durations.count
        if featuredOnly { n += 1 }
        return n
    }
}

/// Remote-first activity catalogue. Falls back to a hardcoded list only if
/// the API call fails (network off, server down, or decoding error).
@MainActor
final class ActivitiesRemoteStore: ObservableObject {
    static let shared = ActivitiesRemoteStore()

    @Published private(set) var activities: [APIClient.APIActivity] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    /// True after a successful fetch. Consumers use this to decide whether
    /// to render live data or fall back to `Activity.suggestions`.
    @Published private(set) var didLoadRemote: Bool = false

    /// User-persisted selection. Changes are written back to UserDefaults
    /// so they carry across sessions.
    @Published var filters: FreeFilterSelection {
        didSet { persist() }
    }

    private static let filtersKey = "pakt_free_filters"
    private let api = APIClient.shared

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.filtersKey),
           let decoded = try? JSONDecoder().decode(FreeFilterSelection.self, from: data) {
            self.filters = decoded
        } else {
            self.filters = FreeFilterSelection()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: Self.filtersKey)
        }
    }

    /// Fetch with the currently selected categories / search / featured flag.
    /// Duration filtering happens client-side (see `filteredActivities`).
    func load(cityId: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let cats = Array(filters.categories)
            let fetched = try await api.listActivities(
                cityId: cityId,
                categories: cats,
                query: filters.searchText.isEmpty ? nil : filters.searchText,
                featured: filters.featuredOnly ? true : nil,
                limit: 100
            )
            activities = fetched
            didLoadRemote = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.d("[ActivitiesRemoteStore] load error: \(error)")
            // Leave didLoadRemote unchanged — UI falls back if it's still false.
        }
    }

    /// Client-side duration filter over the fetched list.
    var filteredActivities: [APIClient.APIActivity] {
        guard !filters.durations.isEmpty else { return activities }
        return activities.filter { act in
            filters.durations.contains { $0.matches(act.durationMinutes) }
        }
    }
}
