import SwiftUI
import MapKit

/// Map surface whose behaviour is driven by the Log Off page's active chip.
///
/// - `For you` → the 20 curated picks plotted as pins with a liquid-glass
///   preview card floating above the currently selected pin.
/// - `Today` → only events where ≥1 friend is going, rendered as friend
///   avatar clusters (no other pins).
/// - `Weekend` → same friend-avatar approach plus a Friday / Saturday /
///   Sunday day picker in the top chip strip.
/// - `Later` → pins for every geolocated event that passes the parent's
///   filter selection.
struct FullMapSheet: View {
    let seedEvents: [APIClient.APIEventListRow]
    let cityId: String
    let cityName: String
    let parentFilter: EventsFeedView.FilterChip
    /// The 20 events currently shown in the For You feed. Only consumed when
    /// `parentFilter == .forYou`, so the map matches what the user sees.
    let forYouEvents: [APIClient.APIEventListRow]
    let onPick: (APIClient.APIEventListRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var allEvents: [APIClient.APIEventListRow] = []
    @State private var loading = false
    @State private var currentSpan: Double = 0.05
    @State private var selectedForPreview: APIClient.APIEventListRow? = nil
    @State private var weekendDay: WeekendDay = .friday

    /// Fri / Sat / Sun picker shown only when `parentFilter == .weekend`.
    /// Determines which 24-hour slice of the weekend window the map surfaces.
    enum WeekendDay: String, CaseIterable, Identifiable {
        case friday, saturday, sunday
        var id: String { rawValue }
        var label: String {
            switch self {
            case .friday:   return "Friday"
            case .saturday: return "Saturday"
            case .sunday:   return "Sunday"
            }
        }
        /// Calendar.weekday value (1=Sun ... 7=Sat).
        var weekday: Int {
            switch self {
            case .sunday:   return 1
            case .friday:   return 6
            case .saturday: return 7
            }
        }
    }

    /// Date range for the current parent chip. Weekend narrows further via
    /// the day picker. `.later` respects the parent's 14-day display budget
    /// so we never dump a 90-day pile of pins.
    private var window: (start: Date, end: Date) {
        let now = Date()
        let cal = Calendar.current
        switch parentFilter {
        case .today:
            let cutoff = cal.date(byAdding: .day, value: 1, to: now)
                .flatMap { cal.date(bySettingHour: 5, minute: 0, second: 0, of: $0) } ?? now
            return (now, cutoff)
        case .weekend:
            return dayWindow(for: weekendDay, from: now)
        case .forYou, .later, .myEvents:
            let end = cal.date(byAdding: .day, value: 14, to: now) ?? now
            return (now, end)
        }
    }

    /// 24-hour slice [00:00, 24:00] of the chosen weekend day, with a small
    /// extension into early Monday so club nights crossing midnight still
    /// register as "Saturday".
    private func dayWindow(for day: WeekendDay, from now: Date) -> (Date, Date) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        // Find the next occurrence of the target weekday (including today).
        let offset = (day.weekday - weekday + 7) % 7
        let base = cal.date(byAdding: .day, value: offset, to: now) ?? now
        let start = cal.date(bySettingHour: 0, minute: 0, second: 0, of: base) ?? base
        let endBase = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let end = cal.date(bySettingHour: 5, minute: 0, second: 0, of: endBase) ?? endBase
        return (start, end)
    }

    /// Events shown as pins. Selection differs per chip.
    private var pinEvents: [APIClient.APIEventListRow] {
        switch parentFilter {
        case .forYou:
            return forYouEvents.filter(hasCoord)
        case .today, .weekend:
            // Friend-avatar-centric: only events with ≥1 friend going.
            let (start, end) = window
            return allEvents
                .filter(hasCoord)
                .filter { $0.friendsGoingCount > 0 && !$0.friendNames.isEmpty }
                .filter { $0.date >= start && $0.date < end }
        case .later, .myEvents:
            let (start, end) = window
            return allEvents
                .filter(hasCoord)
                .filter { $0.date >= start && $0.date < end }
        }
    }

    private func hasCoord(_ row: APIClient.APIEventListRow) -> Bool {
        guard let lat = row.venueLat, let lng = row.venueLng else { return false }
        return lat != 0 || lng != 0
    }

    /// How many avatars to show per cluster based on current zoom.
    private var visibleAvatarsPerCluster: Int {
        if currentSpan > 0.05 { return 1 }
        if currentSpan > 0.015 { return 3 }
        return 6
    }

    private var navTitle: String {
        let count = pinEvents.count
        switch parentFilter {
        case .forYou:
            return "For you · \(count) picks"
        case .today:
            let friends = pinEvents.reduce(0) { $0 + $1.friendsGoingCount }
            return "\(friends) friend\(friends == 1 ? "" : "s") today"
        case .weekend:
            let friends = pinEvents.reduce(0) { $0 + $1.friendsGoingCount }
            return "\(friends) friend\(friends == 1 ? "" : "s") \(weekendDay.label.lowercased())"
        case .later:
            return "\(count) place\(count == 1 ? "" : "s") upcoming"
        case .myEvents:
            return "\(count) place\(count == 1 ? "" : "s") in your agenda"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                    ForEach(pinEvents) { ev in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: ev.venueLat ?? 0,
                            longitude: ev.venueLng ?? 0
                        ), anchor: .center) {
                            Button {
                                // Two-step tap for every mode: first tap on a
                                // pin surfaces the liquid-glass preview card;
                                // tapping that card opens full detail.
                                selectedForPreview = ev
                            } label: {
                                annotationView(for: ev)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .ignoresSafeArea(edges: .bottom)
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    currentSpan = max(ctx.region.span.latitudeDelta,
                                      ctx.region.span.longitudeDelta)
                }

                VStack(spacing: 10) {
                    if parentFilter == .weekend {
                        weekendDayChips
                    }
                    if pinEvents.isEmpty {
                        emptyState
                    }
                    Spacer()
                }
                .padding(.top, 8)

                // Liquid-glass preview card, anchored bottom. Shown across
                // every chip so a pin tap always previews before committing
                // to the full detail sheet.
                if let preview = selectedForPreview {
                    VStack {
                        Spacer()
                        liquidGlassPreview(preview)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.text)
                    }
                    .accessibilityLabel("Close map")
                }
            }
            .task {
                if allEvents.isEmpty {
                    allEvents = seedEvents
                    fit(pinEvents)
                }
                await fetchAll()
            }
            .onChange(of: pinEvents.map(\.id)) { _, _ in fit(pinEvents) }
            .onChange(of: weekendDay) { _, _ in fit(pinEvents) }
        }
        .presentationDetents([.large])
    }

    // MARK: - Subviews

    @ViewBuilder
    private func annotationView(for ev: APIClient.APIEventListRow) -> some View {
        switch parentFilter {
        case .today, .weekend:
            friendClusterMarker(ev)
        case .forYou:
            forYouPinMarker(ev)
        case .later, .myEvents:
            placePinMarker(ev)
        }
    }

    private var weekendDayChips: some View {
        HStack(spacing: 8) {
            ForEach(WeekendDay.allCases) { d in
                let active = weekendDay == d
                Button { weekendDay = d } label: {
                    Text(d.label)
                        .font(.system(size: 13, weight: active ? .bold : .semibold))
                        .foregroundColor(active ? .white : Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(active ? Theme.text : Color(UIColor.systemBackground).opacity(0.95))
                        )
                        .overlay(Capsule().strokeBorder(Theme.separator.opacity(0.4), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyStateText: String {
        if loading { return "Loading..." }
        switch parentFilter {
        case .forYou:   return "No picks with a venue yet"
        case .today:    return "No friends out today"
        case .weekend:  return "No friends out \(weekendDay.label.lowercased())"
        case .later:    return "No places to show"
        case .myEvents: return "Nothing in your agenda yet"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: loading ? "arrow.triangle.2.circlepath" : "mappin.slash")
                .font(.system(size: 28))
                .foregroundColor(Theme.textMuted)
            Text(emptyStateText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bg.opacity(0.95)))
    }

    /// Liquid-glass style preview card shown at the bottom of the map when
    /// a For You pin is tapped. Tap the card → open event detail.
    @ViewBuilder
    private func liquidGlassPreview(_ row: APIClient.APIEventListRow) -> some View {
        Button {
            onPick(row)
        } label: {
            HStack(spacing: 12) {
                if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.bgCard)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "ticket.fill")
                                .foregroundColor(Theme.textMuted)
                        )
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !row.location.isEmpty {
                        Text(row.location)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    if row.friendsGoingCount > 0 {
                        Text("\(row.friendsGoingCount) friend\(row.friendsGoingCount > 1 ? "s" : "") going")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.orange)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(12)
            .background(
                ZStack {
                    // Approximate liquid glass: ultraThinMaterial + subtle
                    // gradient overlay + thin border, plus a soft shadow.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pin markers

    /// Small orange pin used for For You events. Subtle so the preview card
    /// does the visual work. A tiny friend-count badge hangs underneath when
    /// friends are going.
    @ViewBuilder
    private func forYouPinMarker(_ ev: APIClient.APIEventListRow) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.orange))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            if ev.friendsGoingCount > 0 {
                Text("\(ev.friendsGoingCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.text))
            }
        }
    }

    /// Category-coloured place pin (Later / My events). No avatars.
    @ViewBuilder
    private func placePinMarker(_ ev: APIClient.APIEventListRow) -> some View {
        let cat = ev.category ?? ""
        VStack(spacing: 2) {
            Image(systemName: pinIcon(for: cat))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(pinColor(for: cat)))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            if ev.friendsGoingCount > 0 {
                Text("\(ev.friendsGoingCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.orange))
            }
        }
    }

    private func pinIcon(for category: String) -> String {
        switch category {
        case "clubbing": return "music.note"
        case "open_air": return "sun.max.fill"
        case "concert":  return "guitars"
        case "course":   return "figure.run"
        case "sport":    return "sportscourt.fill"
        case "food":     return "fork.knife"
        case "art":      return "paintpalette.fill"
        default:         return "mappin.circle.fill"
        }
    }

    private func pinColor(for category: String) -> Color {
        switch category {
        case "clubbing": return Color.purple
        case "open_air": return Color.orange
        case "concert":  return Color.pink
        case "course":   return Theme.green
        case "sport":    return Color.blue
        case "food":     return Color.red
        case "art":      return Color.teal
        default:         return Theme.text
        }
    }

    /// Friend-avatar cluster marker, used for Today and Weekend modes.
    /// Rosette layout: avatars tucked into a near-square shape instead of
    /// spreading into a horizontal line. Overflow becomes a "+N" slot.
    @ViewBuilder
    private func friendClusterMarker(_ ev: APIClient.APIEventListRow) -> some View {
        let names = ev.friendNames
        let ids = ev.friendIds ?? []
        let maxVisible = visibleAvatarsPerCluster
        let shown = min(names.count, maxVisible)
        let extra = ev.friendsGoingCount - shown
        let total = shown + (extra > 0 ? 1 : 0)
        let avatarSize: CGFloat = total <= 1 ? 42 : (total <= 3 ? 36 : 30)
        let containerSize: CGFloat = total <= 1 ? avatarSize : avatarSize * 1.9

        ZStack {
            ForEach(0..<shown, id: \.self) { i in
                let offset = rosetteOffset(index: i, total: total, radius: containerSize / 2 - avatarSize / 2)
                FriendPhotoCircle(
                    uid: ids[safe: i] ?? "",
                    name: names[i],
                    size: avatarSize
                )
                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(offset)
                .zIndex(Double(shown - i))
            }
            if extra > 0 {
                let offset = rosetteOffset(index: shown, total: total, radius: containerSize / 2 - avatarSize / 2)
                Text("+\(extra)")
                    .font(.system(size: avatarSize * 0.32, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(Theme.text))
                    .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(offset)
                    .zIndex(-1)
            }
        }
        .frame(width: containerSize, height: containerSize)
    }

    private func rosetteOffset(index: Int, total: Int, radius: CGFloat) -> CGSize {
        if total <= 1 { return .zero }
        if total == 2 {
            let x = index == 0 ? -radius * 0.7 : radius * 0.7
            return CGSize(width: x, height: 0)
        }
        if total == 3 {
            switch index {
            case 0: return CGSize(width: 0, height: -radius * 0.75)
            case 1: return CGSize(width: -radius * 0.75, height: radius * 0.5)
            default: return CGSize(width: radius * 0.75, height: radius * 0.5)
            }
        }
        let angle = -.pi / 2 + 2 * .pi * Double(index) / Double(total)
        return CGSize(
            width: CGFloat(cos(angle)) * radius,
            height: CGFloat(sin(angle)) * radius
        )
    }

    // MARK: - Data

    private func fetchAll() async {
        loading = true
        defer { loading = false }
        let from = Date()
        let to = Calendar.current.date(byAdding: .day, value: 14, to: from) ?? from
        do {
            let events = try await APIClient.shared.listEvents(
                cityId: cityId,
                from: from,
                to: to,
                limit: 200
            )
            allEvents = events
        } catch {
            // Keep seed events, map still renders whatever we have.
        }
    }

    private func fit(_ items: [APIClient.APIEventListRow]) {
        let coords = items.compactMap { row -> CLLocationCoordinate2D? in
            guard let lat = row.venueLat, let lng = row.venueLng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard let first = coords.first else { return }
        if coords.count == 1 {
            cameraPosition = .region(MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
            return
        }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.01)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}
