import SwiftUI

/// Shared profile "events attending" section, used by both MyEventsSection
/// (own profile) and FriendEventsSection (friend profile). Fetches via the
/// legacy /users/{id}/events endpoint (which returns events the user has
/// RSVP'd to, both going and interested), renders them as tappable cards,
/// and opens EventDetailSheetRemote on tap.
struct UserEventsSectionView: View {
    let userId: String
    let title: String
    let emptyMessage: String
    let showEmptyState: Bool

    @State private var events: [APIClient.APIUserEvent] = []
    @State private var loaded = false
    @State private var selectedRow: APIClient.APIEventListRow?
    @State private var loadingDetailId: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM · HH'h'mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !events.isEmpty {
                header
                cardList
            } else if loaded && showEmptyState {
                header
                emptyCard
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
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(Theme.textFaint)
                .tracking(2)
            Spacer()
            if !events.isEmpty {
                Text("\(events.count)")
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

    private var cardList: some View {
        VStack(spacing: 10) {
            ForEach(events) { event in
                Button {
                    Task { await openDetail(for: event) }
                } label: {
                    cardRow(for: event)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func cardRow(for event: APIClient.APIUserEvent) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            SwiftUI.Group {
                if let url = URL(string: event.imageUrl), !event.imageUrl.isEmpty {
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.15, blue: 0.22), Color(red: 0.22, green: 0.12, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.3))
                    )
                }
            }
            .frame(width: 70, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dateFormatter.string(from: event.date).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.orange)
                    .tracking(0.4)

                Text(event.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !event.location.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textFaint)
                        Text(event.location)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // Status badge + loader
            VStack(spacing: 4) {
                if loadingDetailId == event.id {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                statusBadge(event.status)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
    }

    private func statusBadge(_ status: String) -> some View {
        let label: String
        let color: Color
        switch status {
        case "going":
            label = "Going"
            color = Theme.green
        case "interested":
            label = "Interested"
            color = Theme.orange
        case "attended":
            label = "Attended"
            color = Theme.textMuted
        default:
            label = status
            color = Theme.textMuted
        }
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(Theme.textFaint)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.bgCard)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Detail loading

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
                myRsvp: detail.myRsvp,
                friendsGoingCount: detail.friendsGoingCount,
                friendNames: detail.friendNames
            )
        }
    }
}
