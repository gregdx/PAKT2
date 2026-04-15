import Foundation
import Combine
import EventKit

/// Adds PAKT events to the user's Apple Calendar on demand.
///
/// Writes to a dedicated `PAKT` calendar so our entries never pollute the
/// user's primary calendar — if they turn sync off and clear the PAKT
/// calendar, none of their other data is affected.
///
/// Deliberately minimal: `addEvent` + `removeEvent` only. No background
/// push, no two-way sync. Called explicitly from the UI so users understand
/// when something lands on their calendar.
@MainActor
final class CalendarSyncManager: ObservableObject {
    static let shared = CalendarSyncManager()
    private let store = EKEventStore()
    private let paktCalendarTitle = "PAKT"

    /// Published so SwiftUI views can show the current permission state and
    /// prompt the user to re-grant access from Settings if needed.
    @Published private(set) var authorization: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    enum CalendarError: Error {
        case accessDenied
        case noWritableSource
        case addFailed(String)
    }

    /// Triggers the iOS permission prompt on first call; returns immediately
    /// thereafter with the cached decision. Uses the iOS 17+ full-access API
    /// and falls back to the legacy API on older versions.
    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        // `.authorized` is the pre-iOS-17 "full access" value and is deprecated
        // in favour of `.fullAccess`. Accept both so the check keeps working
        // for users still on older OS versions without emitting a warning.
        if #available(iOS 17.0, *), status == .fullAccess {
            authorization = status
            return
        }
        if status == .denied || status == .restricted {
            authorization = status
            throw CalendarError.accessDenied
        }
        if #available(iOS 17.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            authorization = EKEventStore.authorizationStatus(for: .event)
            if !granted { throw CalendarError.accessDenied }
        } else {
            let granted: Bool = try await withCheckedThrowingContinuation { cont in
                store.requestAccess(to: .event) { ok, err in
                    if let err = err { cont.resume(throwing: err); return }
                    cont.resume(returning: ok)
                }
            }
            authorization = EKEventStore.authorizationStatus(for: .event)
            if !granted { throw CalendarError.accessDenied }
        }
    }

    /// Returns the dedicated `PAKT` calendar, creating it on the first
    /// writable source (iCloud preferred, then local) if it doesn't exist.
    private func paktCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == paktCalendarTitle }) {
            return existing
        }
        let sources = store.sources
        // Prefer iCloud so the calendar syncs across the user's devices.
        let source = sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") })
                  ?? sources.first(where: { $0.sourceType == .local })
                  ?? sources.first
        guard let source = source else { throw CalendarError.noWritableSource }

        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = paktCalendarTitle
        cal.source = source
        cal.cgColor = UIColor(red: 0.98, green: 0.45, blue: 0.15, alpha: 1).cgColor
        do {
            try store.saveCalendar(cal, commit: true)
            return cal
        } catch {
            throw CalendarError.addFailed(error.localizedDescription)
        }
    }

    /// Upsert-by-identifier: if a calendar event with `ekIdentifier` already
    /// exists we update it in place so re-syncing the same PAKT event after
    /// an edit doesn't create duplicates. Returns the EKEvent identifier so
    /// the caller can store it alongside the PAKT event if needed.
    @discardableResult
    func addEvent(
        title: String,
        start: Date,
        end: Date?,
        location: String,
        notes: String,
        existingIdentifier: String? = nil
    ) async throws -> String {
        try await requestAccess()
        let calendar = try paktCalendar()

        let ek: EKEvent = {
            if let id = existingIdentifier, let match = store.event(withIdentifier: id) {
                return match
            }
            return EKEvent(eventStore: store)
        }()
        ek.calendar = calendar
        ek.title = title
        ek.startDate = start
        // Default to a 2-hour block when the event has no end time — most
        // club nights / concerts don't expose one from RA.
        ek.endDate = end ?? start.addingTimeInterval(2 * 3600)
        ek.location = location
        ek.notes = notes.isEmpty ? nil : notes

        do {
            try store.save(ek, span: .thisEvent, commit: true)
            return ek.eventIdentifier ?? ""
        } catch {
            throw CalendarError.addFailed(error.localizedDescription)
        }
    }

    /// Remove a previously-synced event by its EKEvent identifier. Silent
    /// no-op if the event is already gone (user deleted it manually).
    func removeEvent(identifier: String) async throws {
        try await requestAccess()
        guard let ek = store.event(withIdentifier: identifier) else { return }
        do {
            try store.remove(ek, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.addFailed(error.localizedDescription)
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
