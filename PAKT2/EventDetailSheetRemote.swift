import SwiftUI
import MapKit

/// Event detail sheet driven by APIEventListRow (from the feed) and backed by
/// EventsRemoteStore.fetchDetail for the full friend attendee list.
///
/// Read-only in Step 2 — CTA buttons (Interested / Going) are shown but
/// wired as stubs that will be connected to POST /v1/events/:id/rsvp in Step 3.
struct EventDetailSheetRemote: View {
    let row: APIClient.APIEventListRow

    @Environment(\.dismiss) var dismiss
    @StateObject private var store = EventsRemoteStore.shared
    @State private var detail: APIClient.APIEventDetail?
    @State private var currentRSVP: String?  // "going" | "interested" | nil
    @State private var rsvpBusy = false
    @State private var showSharePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroImage
                    content
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.text)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(.ultraThinMaterial)
                            )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                currentRSVP = row.myRsvp
                detail = await store.fetchDetail(id: row.id)
                if let d = detail { currentRSVP = d.myRsvp }
            }
            .sheet(isPresented: $showSharePicker) {
                ShareEventToFriendSheet(eventId: row.id, eventTitle: row.title)
                    .environmentObject(AppState.shared)
            }
        }
        // True liquid glass backdrop on the sheet itself. On iOS 26+ this
        // uses the native .glassEffect material; on earlier iOS it falls
        // back to .ultraThinMaterial which already has the blurred-glass
        // look.
        .presentationBackground {
            ZStack {
                if #available(iOS 26, *) {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 0))
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero image

    @ViewBuilder
    private var heroImage: some View {
        ZStack(alignment: .topTrailing) {
            if let url = URL(string: row.imageUrl), !row.imageUrl.isEmpty {
                GeometryReader { geo in
                    CachedAsyncImage(url: url)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: 240)
                        .clipped()
                }
                .frame(height: 240)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.1, blue: 0.18), Color(red: 0.22, green: 0.1, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 240)
                .overlay(
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.25))
                )
            }

            if row.source == "ra" {
                Text("Resident Advisor")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleBlock
            metaBlock
            mapCTA
            if row.friendsGoingCount > 0 || !(detail?.friendAttendees.isEmpty ?? true) {
                Divider().padding(.vertical, 4)
                friendsBlock
            }
            ctaRow
            if !row.description.isEmpty {
                Divider().padding(.vertical, 4)
                descriptionBlock
            }
            ticketCTA
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatDateLong(row.date))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.orange)
                .tracking(0.5)

            Text(row.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !row.location.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(Theme.textMuted)
                    Text(row.location)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
            }
            if !row.address.isEmpty {
                Text(row.address)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
                    .padding(.leading, 26)
            }
        }
    }

    @ViewBuilder
    private var mapCTA: some View {
        if !row.address.isEmpty {
            Button {
                openInMaps()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                    Text("Open in Google Maps")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.bgCard)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var friendsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(effectiveFriendCount) friend\(effectiveFriendCount > 1 ? "s" : "") going")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.text)

            if let detail = detail, !detail.friendAttendees.isEmpty {
                VStack(spacing: 8) {
                    ForEach(detail.friendAttendees) { friend in
                        NavigationLink {
                            FriendProfileView(
                                user: AppUser(
                                    id: friend.userId,
                                    firstName: friend.username,
                                    email: ""
                                ),
                                inline: true
                            )
                            .environmentObject(AppState.shared)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Theme.bgCard)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(String(friend.username.prefix(1)).uppercased())
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(Theme.textMuted)
                                    )
                                Text(friend.username)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                statusBadge(friend.status)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Theme.textFaint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !row.friendNames.isEmpty {
                Text(row.friendNames.joined(separator: ", "))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let label: String
        let color: Color
        switch status {
        case "going":
            label = "Y va"
            color = Theme.green
        case "interested":
            label = "Interested"
            color = Theme.orange
        default:
            label = status
            color = Theme.textMuted
        }
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private var ctaRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                rsvpButton(
                    label: currentRSVP == "interested" ? "Interested ✓" : "Interested",
                    systemImage: "star",
                    tint: Theme.orange,
                    active: currentRSVP == "interested"
                ) {
                    Task { await toggleRSVP(status: "interested") }
                }
                rsvpButton(
                    label: currentRSVP == "going" ? "Going ✓" : "Going",
                    systemImage: "checkmark.circle",
                    tint: Theme.green,
                    active: currentRSVP == "going"
                ) {
                    Task { await toggleRSVP(status: "going") }
                }
            }
            Button {
                showSharePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                    Text("Share with a friend")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.bgCard)
                )
            }
            .buttonStyle(.plain)
        }
        .disabled(rsvpBusy)
        .opacity(rsvpBusy ? 0.6 : 1)
    }

    private func toggleRSVP(status: String) async {
        guard !rsvpBusy else { return }
        rsvpBusy = true
        defer { rsvpBusy = false }

        // Tapping the same status again = un-RSVP
        if currentRSVP == status {
            if await store.removeRSVP(eventId: row.id) {
                currentRSVP = nil
            }
        } else {
            if await store.setRSVP(row: row, status: status) {
                currentRSVP = status
            }
        }
        // Refresh detail for friend list counts
        detail = await store.fetchDetail(id: row.id, forceRefresh: true)
    }

    private func rsvpButton(
        label: String,
        systemImage: String,
        tint: Color,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(label)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(active ? .white : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(active ? tint : tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.text)
            Text(row.description)
                .font(.system(size: 14))
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var ticketCTA: some View {
        if let url = URL(string: row.sourceUrl), !row.sourceUrl.isEmpty {
            Link(destination: url) {
                HStack {
                    Image(systemName: "ticket.fill")
                    Text(ticketLabel)
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.text)
                )
            }
        }
    }

    private var ticketLabel: String {
        switch row.source {
        case "ra": return "View on Resident Advisor"
        default:   return "Organizer's website"
        }
    }

    // MARK: - Helpers

    private var effectiveFriendCount: Int {
        if let detail = detail { return detail.friendAttendees.count }
        return row.friendsGoingCount
    }

    private func formatDateLong(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE d MMMM · HH:mm"
        return formatter.string(from: date).uppercased()
    }

    private func openInMaps() {
        let lat = row.venueLat ?? 50.8503
        let lng = row.venueLng ?? 4.3517
        let label = (row.location.isEmpty ? row.title : row.location)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Try Google Maps first, fall back to Apple Maps
        let gmapsURL = URL(string: "comgooglemaps://?q=\(label)&center=\(lat),\(lng)&zoom=16")
        if let gmapsURL, UIApplication.shared.canOpenURL(gmapsURL) {
            UIApplication.shared.open(gmapsURL)
        } else if let webURL = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)&query_place_id=\(label)") {
            UIApplication.shared.open(webURL)
        }
    }
}
