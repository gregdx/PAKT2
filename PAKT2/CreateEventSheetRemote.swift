import SwiftUI

/// Facebook-style user event creation sheet backed by POST /v1/events.
///
/// Fields: title, description, date/time, end time (optional), location,
/// address, visibility radio (Public / Amis only / Sur invitation), and
/// (when "Sur invitation") a friend picker for the invitee list.
///
/// On success, the parent view is called back with the created APIEventDetail
/// so it can refresh its feed and optionally push to the detail sheet.
struct CreateEventSheetRemote: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var store = EventsRemoteStore.shared
    @ObservedObject private var fm = FriendManager.shared

    // Form state
    @State private var title = ""
    @State private var description = ""
    @State private var date = Date().addingTimeInterval(24 * 3600)  // default tomorrow
    @State private var hasEndDate = false
    @State private var endDate = Date().addingTimeInterval(28 * 3600)
    @State private var location = ""
    @State private var address = ""
    @State private var imageUrl = ""
    @State private var visibility: Visibility = .friends
    @State private var invitedIDs: Set<String> = []

    // UI state
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var didPrefill = false

    /// When non-nil, the sheet switches to edit mode: fields are pre-filled,
    /// submit calls PATCH /events/:id instead of POST /events.
    var editing: APIClient.APIEventDetail? = nil

    /// Callback fired on successful creation. The parent can use this to
    /// trigger a feed reload and/or push the event detail sheet.
    var onCreated: ((APIClient.APIEventDetail) -> Void)? = nil

    /// Callback fired on successful edit. Mirrors onCreated but runs after
    /// PATCH instead of POST.
    var onUpdated: ((APIClient.APIEventDetail) -> Void)? = nil

    private var isEditing: Bool { editing != nil }

    enum Visibility: String, CaseIterable, Identifiable {
        case publicEvent = "public"
        case friends = "friends"
        case invited = "invited"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .publicEvent: return "Public"
            case .friends:     return "Friends only"
            case .invited:     return "Invite only"
            }
        }
        var sublabel: String {
            switch self {
            case .publicEvent: return "Everyone can see and join"
            case .friends:     return "Only your friends can see it"
            case .invited:     return "Only invited people"
            }
        }
        var icon: String {
            switch self {
            case .publicEvent: return "globe"
            case .friends:     return "person.2.fill"
            case .invited:     return "lock.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTitle("Title")
                    titleField

                    sectionTitle("When")
                    datePickers

                    sectionTitle("Where")
                    locationFields

                    sectionTitle("Photo")
                    photoField

                    sectionTitle("Description")
                    descriptionField

                    sectionTitle("Who can see this event?")
                    visibilityPicker

                    if visibility == .invited {
                        sectionTitle("Invite")
                        inviteList
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.red.opacity(0.1))
                            )
                    }

                    submitButton
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .background(Theme.bg)
            .navigationTitle(isEditing ? "Edit event" : "New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { prefillIfNeeded() }
        }
    }

    private func prefillIfNeeded() {
        guard let ev = editing, !didPrefill else { return }
        didPrefill = true
        title = ev.title
        description = ev.description
        date = ev.date
        if let end = ev.endDate {
            hasEndDate = true
            endDate = end
        } else {
            hasEndDate = false
        }
        location = ev.location
        address = ev.address
        imageUrl = ev.imageUrl
        visibility = Visibility(rawValue: ev.visibility) ?? .friends
    }

    private var photoField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Image URL (paste a link)", text: $imageUrl)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
                )
            if let url = URL(string: imageUrl), !imageUrl.isEmpty {
                CachedAsyncImage(url: url)
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Fields

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Theme.textMuted)
            .tracking(0.4)
    }

    private var titleField: some View {
        TextField("e.g. Drinks at Marc's", text: $title)
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
            )
    }

    private var datePickers: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Début", selection: $date)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
                )

            Toggle(isOn: $hasEndDate) {
                Text("End time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
            )

            if hasEndDate {
                DatePicker("Fin", selection: $endDate)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
                    )
            }
        }
    }

    private var locationFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Venue name (e.g. Fuse)", text: $location)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
                )
            TextField("Address (optional)", text: $address)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
                )
        }
    }

    private var descriptionField: some View {
        TextField("Add a description...", text: $description, axis: .vertical)
            .lineLimit(3...6)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
            )
    }

    private var visibilityPicker: some View {
        VStack(spacing: 8) {
            ForEach(Visibility.allCases) { v in
                visibilityRow(v)
            }
        }
    }

    private func visibilityRow(_ v: Visibility) -> some View {
        let selected = visibility == v
        return Button {
            visibility = v
        } label: {
            HStack(spacing: 14) {
                Image(systemName: v.icon)
                    .font(.system(size: 18))
                    .frame(width: 28)
                    .foregroundColor(selected ? Theme.text : Theme.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(v.sublabel)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected ? Theme.green : Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Theme.green.opacity(0.08) : Theme.bgCard)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var inviteList: some View {
        if fm.friends.isEmpty {
            Text("You don't have any friends to invite yet — add some first.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Theme.bgCard)
                )
        } else {
            VStack(spacing: 6) {
                ForEach(fm.friends, id: \.id) { friend in
                    friendRow(friend)
                }
            }
        }
    }

    private func friendRow(_ friend: AppUser) -> some View {
        let isInvited = invitedIDs.contains(friend.id)
        return Button {
            if isInvited {
                invitedIDs.remove(friend.id)
            } else {
                invitedIDs.insert(friend.id)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.bgCard)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(friend.firstName.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                    )
                Text(friend.firstName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Image(systemName: isInvited ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundColor(isInvited ? Theme.green : Theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isInvited ? Theme.green.opacity(0.08) : Theme.bgCard)
            )
        }
        .buttonStyle(.plain)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if submitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text(isEditing ? "Save changes" : "Create event")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canSubmit ? Theme.text : Theme.textFaint)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || submitting)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        store.selectedCityId != nil &&
        (visibility != .invited || !invitedIDs.isEmpty)
    }

    // MARK: - Submit

    private func submit() async {
        errorMessage = nil
        submitting = true
        defer { submitting = false }

        if let editing = editing {
            await submitEdit(for: editing)
            return
        }

        do {
            let detail = try await store.createEvent(
                title: title.trimmingCharacters(in: .whitespaces),
                description: description,
                date: date,
                endDate: hasEndDate ? endDate : nil,
                location: location,
                address: address,
                visibility: visibility.rawValue,
                invitedUserIds: Array(invitedIDs),
                imageUrl: imageUrl
            )
            onCreated?(detail)
            dismiss()
        } catch EventsRemoteStore.CreateEventError.missingTitle {
            errorMessage = "Add a title."
        } catch EventsRemoteStore.CreateEventError.missingCity {
            errorMessage = "Select a city first."
        } catch EventsRemoteStore.CreateEventError.apiError(let msg) {
            errorMessage = "Error:\(msg)"
        } catch {
            errorMessage = "Error:\(error.localizedDescription)"
        }
    }

    private func submitEdit(for ev: APIClient.APIEventDetail) async {
        let iso = ISO8601DateFormatter()
        let body = APIClient.UpdateEventBody(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description,
            date: iso.string(from: date),
            endDate: hasEndDate ? iso.string(from: endDate) : nil,
            clearEndDate: !hasEndDate,
            location: location,
            address: address,
            imageUrl: imageUrl,
            visibility: visibility.rawValue
        )
        do {
            let updated = try await APIClient.shared.updateEvent(id: ev.id, body: body)
            EventsRemoteStore.shared.invalidateDetailCache(id: ev.id)
            onUpdated?(updated)
            dismiss()
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }
}
