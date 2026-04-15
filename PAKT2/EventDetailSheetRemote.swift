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
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var deleteInFlight = false

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
            .sheet(isPresented: $showEditSheet) {
                if let d = detail {
                    CreateEventSheetRemote(
                        editing: d,
                        onUpdated: { updated in
                            detail = updated
                            currentRSVP = updated.myRsvp
                        }
                    )
                }
            }
        }
        // True liquid glass backdrop on the sheet itself. On iOS 26+ this
        // uses the native .glassEffect material; on earlier iOS it falls
        // back to .ultraThinMaterial which already has the blurred-glass
        // look.
        .presentationBackground {
            ZStack {
                if #available(iOS 18, *) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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
                    Text("Open in Maps")
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
            let going = detail?.friendAttendees.filter { $0.status == "going" } ?? []
            if !going.isEmpty {
                HStack(spacing: 6) {
                    Text("Who's going")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.4)
                    Text("\(going.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.green)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.green.opacity(0.14)))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(going) { friend in
                            VStack(spacing: 4) {
                                friendAvatar(friend)
                                Text(friend.username)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                    .frame(maxWidth: 54)
                            }
                        }
                    }
                }
            } else if !row.friendNames.isEmpty {
                HStack(spacing: 6) {
                    Text("Who's going")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.4)
                }
                HStack(spacing: -8) {
                    ForEach(Array(row.friendNames.prefix(6).enumerated()), id: \.offset) { _, name in
                        anonAvatar(name: name, color: Theme.green)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func friendAvatar(_ friend: APIClient.APIEventFriendAttendee) -> some View {
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
            FriendPhotoCircle(uid: friend.userId, name: friend.username, size: 44)
        }
        .buttonStyle(.plain)
    }

    private func anonAvatar(name: String, color: Color) -> some View {
        FriendPhotoCircle(uid: "", name: name, size: 36)
    }

    private var ctaRow: some View {
        VStack(spacing: 10) {
            rsvpButton(
                label: currentRSVP == "going" ? "You're going ✓" : "I'm going",
                systemImage: "checkmark.circle.fill",
                tint: Theme.green,
                active: currentRSVP == "going"
            ) {
                Task { await toggleRSVP(status: "going") }
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

            if isCreator {
                Button { showEditSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text("Edit event")
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

                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete event")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.red.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(rsvpBusy || deleteInFlight)
        .opacity((rsvpBusy || deleteInFlight) ? 0.6 : 1)
        .confirmationDialog(
            "Delete this event?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    deleteInFlight = true
                    let ok = await store.deleteEvent(id: row.id)
                    deleteInFlight = false
                    if ok { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isCreator: Bool {
        guard let creator = detail?.creatorId ?? row.creatorId else { return false }
        return creator == AuthManager.shared.currentUser?.id
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

        // Apple Maps universal link — opens the native Maps app on iOS and
        // maps.apple.com in the browser otherwise. Centres on the venue and
        // labels the pin with the location name.
        if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(label)") {
            UIApplication.shared.open(url)
        }
    }
}
