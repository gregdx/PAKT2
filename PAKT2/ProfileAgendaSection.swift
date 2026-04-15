import SwiftUI

/// Profile Agenda — a real calendar-like grouping of the user's upcoming
/// RSVP'd + created events. Replaces the flat `MyEventsSection` list with
/// Today / Tomorrow / This week / Later buckets.
///
/// Each event ships with an "Add to Apple Calendar" shortcut that pushes
/// the event into a dedicated `PAKT` calendar via `CalendarSyncManager`.
/// We map EKEvent identifiers locally so re-syncing is idempotent (no
/// duplicate rows on the user's real calendar).
struct ProfileAgendaSection: View {
    let userId: String

    @State private var events: [APIClient.APIUserEvent] = []
    @State private var loaded = false
    @State private var selectedRow: APIClient.APIEventListRow?
    @State private var loadingDetailId: String?
    @State private var syncingId: String?
    @State private var syncedIds: Set<String> = Self.loadSyncedIds()
    @State private var lastError: String?

    private static let syncedIdsKey = "pakt_calendar_synced_event_ids"

    private static func loadSyncedIds() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: syncedIdsKey) ?? []
        return Set(raw)
    }

    private static func persist(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: syncedIdsKey)
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeStyle = .short
        return f
    }()

    /// Group events into calendar buckets. Past events are excluded — the
    /// agenda is forward-looking. Buckets are sorted chronologically, with
    /// events inside each bucket also date-ascending.
    private var buckets: [(label: String, events: [APIClient.APIUserEvent])] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let startOfAfterTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday) ?? now
        let startOfNextWeek = cal.date(byAdding: .day, value: 7, to: startOfToday) ?? now

        var today: [APIClient.APIUserEvent] = []
        var tomorrow: [APIClient.APIUserEvent] = []
        var thisWeek: [APIClient.APIUserEvent] = []
        var later: [APIClient.APIUserEvent] = []

        for ev in events {
            // Drop events that already ended. We treat the event date as the
            // cutoff since APIUserEvent doesn't carry an end_date field.
            if ev.date < startOfToday { continue }
            if ev.date < startOfTomorrow { today.append(ev) }
            else if ev.date < startOfAfterTomorrow { tomorrow.append(ev) }
            else if ev.date < startOfNextWeek { thisWeek.append(ev) }
            else { later.append(ev) }
        }

        var out: [(String, [APIClient.APIUserEvent])] = []
        if !today.isEmpty    { out.append(("Today", today.sorted { $0.date < $1.date })) }
        if !tomorrow.isEmpty { out.append(("Tomorrow", tomorrow.sorted { $0.date < $1.date })) }
        if !thisWeek.isEmpty { out.append(("This week", thisWeek.sorted { $0.date < $1.date })) }
        if !later.isEmpty    { out.append(("Later", later.sorted { $0.date < $1.date })) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if buckets.isEmpty && loaded {
                emptyCard
            } else {
                content
            }
        }
        .task {
            guard !loaded else { return }
            events = await EventManager.shared.fetchUserEvents(userId: userId)
            loaded = true
        }
        .sheet(item: $selectedRow) { row in
            EventDetailSheetRemote(row: row)
        }
    }

    private var header: some View {
        HStack {
            Text("Agenda")
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(Theme.textFaint)
                .tracking(2)
            Spacer()
            if !events.isEmpty {
                Text("\(buckets.reduce(0) { $0 + $1.events.count })")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.bgCard))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 18) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                VStack(alignment: .leading, spacing: 8) {
                    Text(bucket.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.8)
                    VStack(spacing: 10) {
                        ForEach(bucket.events) { ev in
                            agendaRow(ev)
                        }
                    }
                }
            }
            if let lastError = lastError {
                Text(lastError)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.red)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func agendaRow(_ ev: APIClient.APIUserEvent) -> some View {
        HStack(spacing: 12) {
            // Time column — just the hour, the bucket already gave the day.
            VStack(spacing: 2) {
                Text(Self.timeFormatter.string(from: ev.date))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            .frame(width: 52)

            // Main card — tap opens detail.
            Button {
                Task { await openDetail(for: ev) }
            } label: {
                HStack(spacing: 12) {
                    thumb(for: ev)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ev.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !ev.location.isEmpty {
                            Text(ev.location)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        }
                        statusBadge(ev.status)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard))
            }
            .buttonStyle(.plain)

            // Calendar sync button — on-demand, never automatic.
            calendarSyncButton(for: ev)
        }
    }

    private func thumb(for ev: APIClient.APIUserEvent) -> some View {
        SwiftUI.Group {
            if let url = URL(string: ev.imageUrl), !ev.imageUrl.isEmpty {
                CachedAsyncImage(url: url)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.15, green: 0.15, blue: 0.22), Color(red: 0.22, green: 0.12, blue: 0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                )
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func calendarSyncButton(for ev: APIClient.APIUserEvent) -> some View {
        let alreadySynced = syncedIds.contains(ev.id)
        Button {
            Task { await toggleCalendar(for: ev) }
        } label: {
            if syncingId == ev.id {
                ProgressView().scaleEffect(0.7).frame(width: 34, height: 34)
            } else {
                Image(systemName: alreadySynced ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(alreadySynced ? Theme.green : Theme.textMuted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.bgCard))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alreadySynced ? "Remove from Apple Calendar" : "Add to Apple Calendar")
    }

    private func statusBadge(_ status: String) -> some View {
        let label: String
        let color: Color
        switch status {
        case "going":
            label = "Going"; color = Theme.green
        case "interested":
            label = "Interested"; color = Theme.orange
        case "attended":
            label = "Attended"; color = Theme.textMuted
        default:
            label = status; color = Theme.textMuted
        }
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(Theme.textFaint)
            Text("Nothing on your agenda yet")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bgCard))
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func openDetail(for event: APIClient.APIUserEvent) async {
        loadingDetailId = event.id
        defer { loadingDetailId = nil }
        if let detail = await EventsRemoteStore.shared.fetchDetail(id: event.id) {
            selectedRow = APIClient.APIEventListRow(
                id: detail.id,
                title: detail.title,
                description: detail.description,
                date: detail.date,
                endDate: detail.endDate,
                location: detail.location,
                address: detail.address,
                source: detail.source,
                sourceUrl: detail.sourceUrl,
                imageUrl: detail.imageUrl,
                cityId: detail.cityId,
                venueLat: detail.venueLat,
                venueLng: detail.venueLng,
                visibility: detail.visibility,
                creatorId: detail.creatorId,
                category: detail.category,
                myRsvp: detail.myRsvp,
                friendsGoingCount: detail.friendsGoingCount,
                friendNames: detail.friendNames,
                friendIds: detail.friendIds
            )
        }
    }

    /// On-demand: add the event to the PAKT Apple Calendar, or remove it if
    /// it's already synced. Stores EKEvent identifier lookup via the PAKT id
    /// in UserDefaults — small and per-device, no backend work needed.
    private func toggleCalendar(for ev: APIClient.APIUserEvent) async {
        syncingId = ev.id
        defer { syncingId = nil }
        lastError = nil

        let idKey = "pakt_ek_id_\(ev.id)"
        let existingEK = UserDefaults.standard.string(forKey: idKey)

        if syncedIds.contains(ev.id), let existing = existingEK {
            // Remove flow
            do {
                try await CalendarSyncManager.shared.removeEvent(identifier: existing)
                UserDefaults.standard.removeObject(forKey: idKey)
                syncedIds.remove(ev.id)
                Self.persist(syncedIds)
            } catch {
                lastError = "Couldn't remove from Apple Calendar: \(error.localizedDescription)"
            }
            return
        }

        // Add flow
        do {
            let ekId = try await CalendarSyncManager.shared.addEvent(
                title: ev.title,
                start: ev.date,
                end: nil,
                location: ev.location,
                notes: "Synced from PAKT",
                existingIdentifier: existingEK
            )
            if !ekId.isEmpty {
                UserDefaults.standard.set(ekId, forKey: idKey)
                syncedIds.insert(ev.id)
                Self.persist(syncedIds)
            }
        } catch CalendarSyncManager.CalendarError.accessDenied {
            lastError = "Grant calendar access in Settings to sync events."
        } catch {
            lastError = "Couldn't add to Apple Calendar: \(error.localizedDescription)"
        }
    }
}
