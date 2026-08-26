import Foundation
import Persistence

/// One calendar provider. `EventKitSource` today, `GoogleCalendarSource` in
/// Phase D, fakes in tests. Everything above this protocol is provider-blind.
public protocol CalendarSource: Sendable {
    var source: CalendarEventSource { get }
    var isAuthorized: Bool { get async }
    func requestAccess() async throws -> Bool
    func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot]
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func delete(sourceID: String) async throws
}
