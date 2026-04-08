import SwiftUI
import PhotosUI

// MARK: - PaktEventCard (compact card in list)

struct PaktEventCard: View {
    let event: PaktEvent
    let myUid: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var friendManager = FriendManager.shared
    @State private var showDetail = false

    private var isGoing: Bool { event.goingIds.contains(myUid) }
    private var isInterested: Bool { event.interestedIds.contains(myUid) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tappable area - opens detail
            Button(action: { showDetail = true }) {
                VStack(alignment: .leading, spacing: 12) {
                    // Photo
                    if let img = event.image {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 160)
                            .clipped()
                            .cornerRadius(14)
                    }

                    // Date + visibility
                    HStack(spacing: 8) {
                        Text(event.formattedDate)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.orange)
                        Spacer()
                        Text(event.isPublic ? L10n.t("public_event") : L10n.t("friends_only"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textFaint)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.bgWarm))
                    }

                    // Title
                    Text(event.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)

                    // Location
                    if !event.address.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textFaint)
                            Text(event.address)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    // Counts + friends
                    HStack(spacing: 14) {
                        if event.goingCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(Theme.green)
                                Text("\(event.goingCount)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            }
                        }
                        if event.interestedCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").font(.system(size: 12)).foregroundColor(Theme.orange)
                                Text("\(event.interestedCount)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Action buttons - NOT inside the Button above
            HStack(spacing: 10) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    eventManager.toggleGoing(eventId: event.id, userId: myUid)
                    if !isGoing { PaktAnalytics.track(.eventGoing) }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isGoing ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 14))
                        Text(L10n.t("going")).font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(isGoing ? Theme.bg : Theme.text)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background {
                        if isGoing { RoundedRectangle(cornerRadius: 10).fill(Theme.green) }
                        else { RoundedRectangle(cornerRadius: 10).fill(.clear).liquidGlass(cornerRadius: 10) }
                    }
                }
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    eventManager.toggleInterested(eventId: event.id, userId: myUid)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isInterested ? "star.fill" : "star").font(.system(size: 14))
                        Text(L10n.t("interested")).font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(isInterested ? Theme.bg : Theme.text)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background {
                        if isInterested { RoundedRectangle(cornerRadius: 10).fill(Theme.orange) }
                        else { RoundedRectangle(cornerRadius: 10).fill(.clear).liquidGlass(cornerRadius: 10) }
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.4)))
        .liquidGlass(cornerRadius: 20, style: .ultraThin)
        .sheet(isPresented: $showDetail) {
            EventDetailSheet2(event: event).environmentObject(appState)
        }
    }
}

// MARK: - Event Detail Sheet (full info)

struct EventDetailSheet2: View {
    let event: PaktEvent
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var friendManager = FriendManager.shared
    @State private var showEdit = false
    @State private var showInvite = false
    @State private var calendarAdded = false
    @State private var showDeleteConfirm = false

    private var myUid: String { appState.currentUID }
    private var isCreator: Bool { event.creatorId == myUid }
    private var isGoing: Bool { currentEvent.goingIds.contains(myUid) }
    private var isInterested: Bool { currentEvent.interestedIds.contains(myUid) }

    private var currentEvent: PaktEvent {
        eventManager.events.first(where: { $0.id == event.id }) ?? event
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.textMuted)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        Spacer()
                        if isCreator {
                            Button(action: { showEdit = true }) {
                                Image(systemName: "pencil").font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.textMuted)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            Button(action: { showDeleteConfirm = true }) {
                                Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.red)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                        }
                    }
                    .padding(.top, 16)

                    // Photo
                    if let img = currentEvent.image {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipped()
                            .cornerRadius(18)
                    }

                    // Date
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 15)).foregroundColor(Theme.orange)
                        Text(currentEvent.formattedDate).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.orange)
                        Spacer()
                        Text(currentEvent.isPublic ? L10n.t("public_event") : L10n.t("friends_only"))
                            .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textFaint)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.bgWarm))
                    }

                    // Title
                    Text(currentEvent.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)

                    // Description
                    if !currentEvent.description.isEmpty {
                        Text(currentEvent.description)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textMuted)
                            .lineSpacing(4)
                    }

                    // Location + Maps
                    if !currentEvent.address.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill").font(.system(size: 20)).foregroundColor(Theme.text)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentEvent.address).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                            }
                            Spacer()
                            if let url = currentEvent.mapsURL {
                                Link(destination: url) {
                                    Text(L10n.t("open_maps"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.blue)
                                }
                            }
                        }
                        .padding(14)
                        .liquidGlass(cornerRadius: 12)
                    }

                    // Created by
                    HStack(spacing: 8) {
                        Text(L10n.t("created_by")).font(.system(size: 14)).foregroundColor(Theme.textFaint)
                        Text(currentEvent.creatorName).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    }

                    // Action buttons
                    HStack(spacing: 10) {
                        Button(action: {
                            if !isGoing { PaktAnalytics.track(.eventGoing) }
                            eventManager.toggleGoing(eventId: event.id, userId: myUid)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isGoing ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 15))
                                Text(L10n.t("going")).font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(isGoing ? Theme.bg : Theme.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background {
                                if isGoing { RoundedRectangle(cornerRadius: 12).fill(Theme.green) }
                                else { RoundedRectangle(cornerRadius: 12).fill(.clear).liquidGlass(cornerRadius: 12) }
                            }
                        }
                        Button(action: { eventManager.toggleInterested(eventId: event.id, userId: myUid) }) {
                            HStack(spacing: 6) {
                                Image(systemName: isInterested ? "star.fill" : "star").font(.system(size: 15))
                                Text(L10n.t("interested")).font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(isInterested ? Theme.bg : Theme.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background {
                                if isInterested { RoundedRectangle(cornerRadius: 12).fill(Theme.orange) }
                                else { RoundedRectangle(cornerRadius: 12).fill(.clear).liquidGlass(cornerRadius: 12) }
                            }
                        }
                    }

                    // Calendar + Invite row
                    HStack(spacing: 10) {
                        Button(action: {
                            guard !calendarAdded else { return }
                            EventManager.addToCalendar(event: currentEvent) { ok in calendarAdded = ok }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: calendarAdded ? "checkmark" : "calendar.badge.plus").font(.system(size: 14))
                                Text(calendarAdded ? L10n.t("added_to_calendar") : L10n.t("add_to_calendar"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .liquidGlass(cornerRadius: 12)
                        }
                        Button(action: { showInvite = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.badge.plus").font(.system(size: 14))
                                Text(L10n.t("invite_friends")).font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .liquidGlass(cornerRadius: 12)
                        }
                    }

                    // Going section
                    if currentEvent.goingCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(L10n.t("going")) (\(currentEvent.goingCount))")
                                .font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(2)
                            ForEach(currentEvent.goingIds, id: \.self) { uid in
                                let name = friendManager.friends.first(where: { $0.id == uid })?.firstName ?? uid.prefix(8).description
                                HStack(spacing: 10) {
                                    AvatarView(name: name, size: 32, color: Theme.green, uid: uid, isMe: uid == myUid)
                                        .environmentObject(appState)
                                    Text(uid == myUid ? L10n.t("you") : name)
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(Theme.green)
                                }
                            }
                        }
                        .padding(14).liquidGlass(cornerRadius: 16)
                    }

                    // Interested section
                    if currentEvent.interestedCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(L10n.t("interested")) (\(currentEvent.interestedCount))")
                                .font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(2)
                            ForEach(currentEvent.interestedIds, id: \.self) { uid in
                                let name = friendManager.friends.first(where: { $0.id == uid })?.firstName ?? uid.prefix(8).description
                                HStack(spacing: 10) {
                                    AvatarView(name: name, size: 32, color: Theme.orange, uid: uid, isMe: uid == myUid)
                                        .environmentObject(appState)
                                    Text(uid == myUid ? L10n.t("you") : name)
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: "star.fill").font(.system(size: 14)).foregroundColor(Theme.orange)
                                }
                            }
                        }
                        .padding(14).liquidGlass(cornerRadius: 16)
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showEdit) {
            CreateEventSheet(editingEvent: currentEvent).environmentObject(appState)
        }
        .sheet(isPresented: $showInvite) {
            InviteToEventSheet(event: currentEvent).environmentObject(appState)
        }
        .confirmationDialog(L10n.t("delete_event"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L10n.t("delete"), role: .destructive) {
                eventManager.deleteEvent(event.id)
                dismiss()
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        }
    }
}

// MARK: - Create / Edit Event Sheet

struct CreateEventSheet: View {
    var editingEvent: PaktEvent? = nil
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var eventManager = EventManager.shared

    @State private var title = ""
    @State private var description = ""
    @State private var address = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var isPublic = true
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil

    var isEditing: Bool { editingEvent != nil }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 17)).foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text(isEditing ? L10n.t("edit_event") : L10n.t("create_event"))
                        .font(.system(size: 16, weight: .medium)).foregroundColor(Theme.textMuted)
                    Spacer()
                    Color.clear.frame(width: 17)
                }
                .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 24)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Photo section
                        SwiftUI.Group {
                            if let data = imageData, let img = UIImage(data: data) {
                                VStack {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(maxWidth: .infinity, maxHeight: 180)
                                            .clipped().cornerRadius(14)
                                        Button(action: { imageData = nil; selectedPhoto = nil }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.white)
                                                .shadow(radius: 4)
                                        }
                                        .padding(8)
                                    }
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "photo").font(.system(size: 14))
                                            Text(L10n.t("change_photo")).font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundColor(Theme.textMuted)
                                        .padding(.vertical, 8)
                                    }
                                }
                            } else {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "photo").font(.system(size: 16))
                                        Text(L10n.t("add_photo")).font(.system(size: 15, weight: .medium))
                                    }
                                    .foregroundColor(Theme.textMuted)
                                    .frame(maxWidth: .infinity).frame(height: 100)
                                    .liquidGlass(cornerRadius: 16)
                                }
                            }
                        }
                        .onChange(of: selectedPhoto) { item in
                            Task {
                                if let data = try? await item?.loadTransferable(type: Data.self) {
                                    imageData = UIImage(data: data)?.jpegData(compressionQuality: 0.5)
                                }
                            }
                        }

                        // Title
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("event_title")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textFaint).tracking(1)
                            TextField(L10n.t("event_title_placeholder"), text: $title)
                                .font(.system(size: 17)).foregroundColor(Theme.text)
                                .padding(14).liquidGlass(cornerRadius: 12)
                        }

                        // Description
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("event_description")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textFaint).tracking(1)
                            TextField(L10n.t("event_desc_placeholder"), text: $description, axis: .vertical)
                                .font(.system(size: 15)).foregroundColor(Theme.text)
                                .lineLimit(3...6).padding(14).liquidGlass(cornerRadius: 12)
                        }

                        // Address (Google Maps style)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("event_location")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textFaint).tracking(1)
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill").font(.system(size: 18)).foregroundColor(Theme.textMuted)
                                TextField(L10n.t("event_location_placeholder"), text: $address)
                                    .font(.system(size: 15)).foregroundColor(Theme.text)
                            }
                            .padding(14).liquidGlass(cornerRadius: 12)
                        }

                        // Date
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("event_date")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textFaint).tracking(1)
                            DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact).labelsHidden()
                        }

                        // Public / Friends only toggle
                        HStack {
                            Text(L10n.t("visibility")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textFaint).tracking(1)
                            Spacer()
                            Picker("", selection: $isPublic) {
                                Text(L10n.t("public_event")).tag(true)
                                Text(L10n.t("friends_only")).tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Save button
                Button(action: saveEvent) {
                    Text(isEditing ? L10n.t("save") : L10n.t("create_event"))
                        .font(.system(size: 17, weight: .bold)).foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.text).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24).padding(.bottom, 40)
                .opacity(title.isEmpty ? 0.4 : 1).disabled(title.isEmpty)
            }
        }
        .onAppear {
            if let e = editingEvent {
                title = e.title; description = e.description; address = e.address
                date = e.date; isPublic = e.isPublic
                imageData = e.imageData ?? EventManager.loadImage(for: e.id)
            }
        }
    }

    private func saveEvent() {
        if var e = editingEvent {
            e.title = title; e.description = description; e.address = address
            e.date = date; e.isPublic = isPublic; e.imageData = imageData
            eventManager.updateEvent(e)
        } else {
            let event = PaktEvent(
                title: title, description: description, date: date,
                address: address, creatorId: appState.currentUID,
                creatorName: appState.userName, imageData: imageData,
                isPublic: isPublic, goingIds: [appState.currentUID]
            )
            eventManager.createEvent(event)
            PaktAnalytics.track(.eventCreated)
        }
        dismiss()
    }
}

// MARK: - Invite Friends to Event

struct InviteToEventSheet: View {
    let event: PaktEvent
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var friendManager = FriendManager.shared
    @ObservedObject private var eventManager = EventManager.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 17)).foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text(L10n.t("invite_friends")).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.textMuted)
                    Spacer()
                    Color.clear.frame(width: 17)
                }
                .padding(.horizontal, 24).padding(.top, 52).padding(.bottom, 24)

                let currentEvent = eventManager.events.first(where: { $0.id == event.id }) ?? event
                let alreadyIn = Set(currentEvent.goingIds + currentEvent.interestedIds)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(friendManager.friends) { friend in
                            let isIn = alreadyIn.contains(friend.id)
                            HStack(spacing: 12) {
                                AvatarView(name: friend.firstName, size: 40, color: Theme.textMuted, uid: friend.id, isMe: false)
                                    .environmentObject(appState)
                                Text(friend.firstName).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.text)
                                Spacer()
                                if isIn {
                                    Text(L10n.t("going")).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.green)
                                } else {
                                    Button(action: {
                                        eventManager.toggleGoing(eventId: event.id, userId: friend.id)
                                    }) {
                                        Text(L10n.t("invite_btn")).font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Theme.text)
                                            .padding(.vertical, 7).padding(.horizontal, 14)
                                            .liquidGlass(cornerRadius: 10)
                                    }
                                }
                            }
                            .padding(.horizontal, 24).padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Friend Events Section (for FriendProfileView)

struct FriendEventsSection: View {
    let userId: String
    @State private var apiEvents: [APIClient.APIUserEvent] = []
    @State private var loaded = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if !apiEvents.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.t("events_attending"))
                        .font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.textFaint).tracking(2)
                        .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        ForEach(apiEvents) { event in
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                                        Text(event.date, style: .date).font(.system(size: 13)).foregroundColor(Theme.orange)
                                        if !event.location.isEmpty {
                                            Text(event.location).font(.system(size: 13)).foregroundColor(Theme.textMuted).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if event.status == "going" {
                                        Text(L10n.t("going")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                                    } else {
                                        Text(L10n.t("interested")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.orange)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                        }
                    }
                    .liquidGlass(cornerRadius: 16)
                    .padding(.horizontal, 24)
                }
            }
        }
        .task {
            guard !loaded else { return }
            apiEvents = await EventManager.shared.fetchUserEvents(userId: userId)
            loaded = true
        }
    }
}
