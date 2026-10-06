// LifeOSKit/Sources/Assistant/CalendarAccess.swift
import Foundation
import Persistence

/// What the tools may read. MainActor because the store's ModelContext is;
/// tools hop to it per call.
@MainActor
public protocol CalendarReading: Sendable {
    func events(from: Date, to: Date) throws -> [CalendarEventSnapshot]
    func snapshot(id: UUID) throws -> CalendarEventSnapshot?
    func freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval]
}

extension CalendarStore: CalendarReading {}

/// The only calendar mutation surface the tools can reach. The app satisfies
/// it with CalendarSync, so every write goes through the provider and a
/// re-sync, exactly like a tap in the UI would.
public protocol CalendarWriting: Sendable {
    /// The event as the cache holds it after the write, so a caller can show
    /// it and find it again by id.
    @discardableResult
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func update(id: UUID, with draft: CalendarEventDraft) async throws
    func delete(id: UUID) async throws
}
