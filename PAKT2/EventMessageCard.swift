import SwiftUI

// MARK: - Event card in chat messages

struct EventMessageCard: View {
    let text: String
    let isMine: Bool
    @ObservedObject private var eventManager = EventManager.shared
    @EnvironmentObject var appState: AppState

    private var parsed: ParsedEvent? { Self.parseEventMessage(text) }
    private var personalMessage: String? { Self.extractPersonalMessage(text) }

    var body: some View {
        if let event = parsed {
            VStack(alignment: .leading, spacing: 0) {
                // Personal message above the card
                if let msg = personalMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlass(cornerRadius: 18)
                        .padding(.bottom, 6)
                }

                // Event card
                VStack(alignment: .leading, spacing: 0) {
                    // Dark header with venue
                    HStack {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                        if let venue = event.venue {
                            Text(venue.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(0.8)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(red: 0.10, green: 0.10, blue: 0.10))

                    VStack(alignment: .leading, spacing: 8) {
                        // Title
                        Text(event.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.text)
                            .lineLimit(2)

                        // Date
                        Text(event.date)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.orange)

                        // Artists
                        if let artists = event.artists, !artists.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textFaint)
                                Text(artists)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textMuted)
                                    .lineLimit(1)
                            }
                        }

                        // Going / Interested buttons
                        let paktId = event.paktId
                        let paktEvent = eventManager.events.first { $0.id == paktId }
                        let isGoing = paktEvent?.goingIds.contains(appState.currentUID) ?? false
                        let isInterested = paktEvent?.interestedIds.contains(appState.currentUID) ?? false

                        HStack(spacing: 8) {
                            Button(action: {
                                ensureEvent(event)
                                eventManager.toggleGoing(eventId: paktId, userId: appState.currentUID)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isGoing ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.system(size: 12))
                                    Text(L10n.t("going"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(isGoing ? .white : Theme.text)
                                .padding(.vertical, 6).padding(.horizontal, 10)
                                .background(isGoing ? Theme.green : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isGoing ? Color.clear : Theme.textFaint.opacity(0.3), lineWidth: 1)
                                )
                            }

                            Button(action: {
                                ensureEvent(event)
                                eventManager.toggleInterested(eventId: paktId, userId: appState.currentUID)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isInterested ? "star.fill" : "star")
                                        .font(.system(size: 12))
                                    Text(L10n.t("interested"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(isInterested ? .white : Theme.text)
                                .padding(.vertical, 6).padding(.horizontal, 10)
                                .background(isInterested ? Theme.orange : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isInterested ? Color.clear : Theme.textFaint.opacity(0.3), lineWidth: 1)
                                )
                            }

                            Spacer()

                            // Open on RA
                            Button(action: {
                                if let url = URL(string: event.url) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Image(systemName: "safari")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textMuted)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(width: 270)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .liquidGlass(cornerRadius: 16)
            }
        } else {
            LinkText(text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .liquidGlass(cornerRadius: 18)
        }
    }

    private func ensureEvent(_ event: ParsedEvent) {
        let paktId = event.paktId
        guard !eventManager.events.contains(where: { $0.id == paktId }) else { return }

        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, HH:mm"
        f.locale = Locale(identifier: "fr_FR")
        let eventDate = f.date(from: event.date) ?? Date()

        eventManager.createEvent(PaktEvent(
            id: paktId,
            title: event.title,
            date: eventDate,
            location: event.venue ?? "",
            address: event.venue ?? "",
            creatorId: "ra",
            creatorName: "Resident Advisor",
            isPublic: true,
            source: "ra",
            sourceUrl: event.url
        ))
    }

    // MARK: - Parsing

    struct ParsedEvent {
        let title: String
        let date: String
        let venue: String?
        let artists: String?
        let url: String

        var paktId: String {
            // Extract RA event ID from URL
            if let range = url.range(of: "\\d+$", options: .regularExpression) {
                return "ra_\(url[range])"
            }
            return "ra_\(url.hashValue)"
        }
    }

    static func parseEventMessage(_ text: String) -> ParsedEvent? {
        guard let urlRange = text.range(of: "https://ra.co/events/\\d+", options: .regularExpression) else {
            return nil
        }
        let url = String(text[urlRange])
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        // Find the event info line (contains " — ")
        guard let infoLine = lines.first(where: { $0.contains(" — ") }) else {
            return ParsedEvent(title: "Event", date: "", venue: nil, artists: nil, url: url)
        }

        var title = infoLine
        var date = ""
        var venue: String? = nil

        if let dashRange = infoLine.range(of: " — ") {
            title = String(infoLine[infoLine.startIndex..<dashRange.lowerBound])
            let rest = String(infoLine[dashRange.upperBound...])
            if let atRange = rest.range(of: " @ ") {
                date = String(rest[rest.startIndex..<atRange.lowerBound])
                venue = String(rest[atRange.upperBound...])
            } else {
                date = rest
            }
        }

        // Artists: line after info line, before URL
        var artists: String? = nil
        if let infoIdx = lines.firstIndex(of: infoLine), infoIdx + 1 < lines.count {
            let nextLine = lines[infoIdx + 1]
            if !nextLine.starts(with: "http") && !nextLine.isEmpty {
                artists = nextLine
            }
        }

        return ParsedEvent(title: title, date: date, venue: venue, artists: artists, url: url)
    }

    /// Extract personal message (lines before the event info)
    static func extractPersonalMessage(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let infoIdx = lines.firstIndex(where: { $0.contains(" — ") && text.contains("ra.co/events/") }) else {
            return nil
        }
        guard infoIdx > 0 else { return nil }
        let msgLines = lines[0..<infoIdx].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return msgLines.isEmpty ? nil : msgLines
    }
}

// MARK: - Text with tappable links

struct LinkText: View {
    let text: String

    var body: some View {
        if let url = extractURL(from: text) {
            VStack(alignment: .leading, spacing: 4) {
                let clean = textWithoutURL
                if !clean.isEmpty {
                    Text(clean)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.text)
                }
                Button(action: { UIApplication.shared.open(url) }) {
                    Text(url.absoluteString)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.blue)
                        .lineLimit(1)
                }
            }
        } else {
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
        }
    }

    private var textWithoutURL: String {
        text.replacingOccurrences(of: "https?://[^\\s]+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractURL(from text: String) -> URL? {
        guard let range = text.range(of: "https?://[^\\s]+", options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }
}

extension String {
    var isRAEventMessage: Bool {
        range(of: "https://ra.co/events/\\d+", options: .regularExpression) != nil
    }
}
