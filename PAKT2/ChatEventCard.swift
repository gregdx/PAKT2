import SwiftUI

/// Renders a shared-event chat bubble. Takes an event id, fetches the full
/// event via EventsRemoteStore (with 5-min detail cache), and shows a compact
/// card with image, title, date, venue, and an RSVP hint. Tapping opens the
/// full EventDetailSheetRemote.
struct ChatEventCard: View {
    let eventId: String
    let isMine: Bool

    @State private var row: APIClient.APIEventListRow?
    @State private var loading = true
    @State private var showDetail = false

    private let store = EventsRemoteStore.shared

    var body: some View {
        SwiftUI.Group {
            if let row = row {
                content(for: row)
                    .onTapGesture { showDetail = true }
                    .sheet(isPresented: $showDetail) {
                        EventDetailSheetRemote(row: row)
                    }
            } else if loading {
                placeholder
            } else {
                errorBubble
            }
        }
        .task {
            if let detail = await store.fetchDetail(id: eventId) {
                row = detailToRow(detail)
            }
            loading = false
        }
    }

    // MARK: - Content

    private func content(for row: APIClient.APIEventListRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                Text("SHARED EVENT")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(0.8)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))

            // Image
            if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                CachedAsyncImage(url: url)
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(row.date))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .tracking(0.4)

                Text(row.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.location.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textFaint)
                        Text(row.location)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                }

                if let rsvp = row.myRsvp {
                    Text(rsvpLabel(rsvp))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 260)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.border.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading event...")
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
    }

    private var errorBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "ticket")
                .foregroundColor(Theme.textFaint)
            Text("Event unavailable")
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE d MMM · HH'h'mm"
        return f.string(from: date).uppercased()
    }

    private func rsvpLabel(_ status: String) -> String {
        switch status {
        case "going":      return "✓ You're going"
        case "interested": return "★ You're interested"
        default:           return ""
        }
    }

    /// EventDetail has all the fields EventListRow has — this is just a
    /// lossless narrowing so we can reuse the EventListRow renderers.
    private func detailToRow(_ d: APIClient.APIEventDetail) -> APIClient.APIEventListRow {
        APIClient.APIEventListRow(
            id: d.id,
            title: d.title,
            description: d.description,
            date: d.date,
            endDate: d.endDate,
            location: d.location,
            address: d.address,
            source: d.source,
            sourceUrl: d.sourceUrl,
            imageUrl: d.imageUrl,
            cityId: d.cityId,
            venueLat: d.venueLat,
            venueLng: d.venueLng,
            visibility: d.visibility,
            creatorId: d.creatorId,
            category: d.category,
            myRsvp: d.myRsvp,
            friendsGoingCount: d.friendsGoingCount,
            friendNames: d.friendNames,
            friendIds: d.friendIds
        )
    }
}
