// LifeOSKit/Sources/Assistant/CalendarTools.swift
import Foundation
import FoundationModels
import Insights
import Persistence

@Generable
struct RangeArguments {
    @Guide(description: "ISO-8601 range start, e.g. 2026-08-26T00:00:00Z")
    var start: String
    @Guide(description: "ISO-8601 range end")
    var end: String
}

@Generable
struct FreeTimeArguments {
    @Guide(description: "ISO-8601 range start")
    var start: String
    @Guide(description: "ISO-8601 range end")
    var end: String
    @Guide(description: "Minimum slot length in minutes")
    var durationMinutes: Int
}

@Generable
struct EventDraftArguments {
    @Guide(description: "Event title")
    var title: String
    @Guide(description: "ISO-8601 start")
    var start: String
    @Guide(description: "ISO-8601 end")
    var end: String
    @Guide(description: "true only for all-day events")
    var isAllDay: Bool
    @Guide(description: "Location, or empty when there is none")
    var location: String
    @Guide(description: "Notes, or empty when there are none")
    var notes: String
}

@Generable
struct UpdateArguments {
    @Guide(description: "The event id exactly as get_events reported it")
    var id: String
    @Guide(description: "Event title")
    var title: String
    @Guide(description: "ISO-8601 start")
    var start: String
    @Guide(description: "ISO-8601 end")
    var end: String
    @Guide(description: "true only for all-day events")
    var isAllDay: Bool
    @Guide(description: "Location, or empty when there is none")
    var location: String
    @Guide(description: "Notes, or empty when there are none")
    var notes: String
}

@Generable
struct DeleteArguments {
    @Guide(description: "The event id exactly as get_events reported it")
    var id: String
}

/// Renders one event the way every tool result and the inline context do,
/// id first so the model can only reference ids it has actually seen.
func eventLine(_ event: CalendarEventSnapshot, timeZone: TimeZone = .current) -> String {
    let start = ToolDates.render(event.startDate, timeZone: timeZone)
    let end = ToolDates.render(event.endDate, timeZone: timeZone)
    let span = event.isAllDay ? "all day" : "\(start) to \(end)"
    return "\(event.id.uuidString) | \(span) | \(event.title)"
}

struct GetEventsTool: CoachTool {
    let reading: any CalendarReading
    let name = "get_events"
    let description = "List calendar events in a date range, with their ids."
    var parameters: GenerationSchema { RangeArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Checked your calendar" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try RangeArguments(arguments)
        let from = try ToolDates.parse(args.start)
        let to = try ToolDates.parse(args.end)
        let events = try await reading.events(from: from, to: to)
        guard !events.isEmpty else { return "No events in that range." }
        return events.map { eventLine($0) }.joined(separator: "\n")
    }
}

struct FindFreeTimeTool: CoachTool {
    let reading: any CalendarReading
    let name = "find_free_time"
    let description = "Find open slots of at least a given length in a date range."
    var parameters: GenerationSchema { FreeTimeArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Looked for free time" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try FreeTimeArguments(arguments)
        let from = try ToolDates.parse(args.start)
        let to = try ToolDates.parse(args.end)
        let slots = try await reading.freeSlots(from: from, to: to, durationMinutes: args.durationMinutes)
        guard !slots.isEmpty else { return "No free slots of that length in the range." }
        let lines = slots.map { slot in
            "free \(ToolDates.render(slot.start, timeZone: .current)) to \(ToolDates.render(slot.end, timeZone: .current))"
        }
        return lines.joined(separator: "\n")
    }
}

struct AnalyzeScheduleTool: CoachTool {
    let reading: any CalendarReading
    let name = "analyze_schedule"
    let description = "Summarize how busy a date range is: event count and busy hours."
    var parameters: GenerationSchema { RangeArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Analyzed your schedule" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try RangeArguments(arguments)
        let from = try ToolDates.parse(args.start)
        let to = try ToolDates.parse(args.end)
        let events = try await reading.events(from: from, to: to)
        let timed = events.filter { !$0.isAllDay }
        let busySeconds = timed.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let busyHours = Int((busySeconds / 3_600).rounded())
        return "\(events.count) events, \(timed.count) with times, about \(busyHours) busy hours."
    }
}

struct CreateEventTool: CoachTool {
    let writing: any CalendarWriting
    let name = "create_event"
    let description = "Create a calendar event."
    var parameters: GenerationSchema { EventDraftArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Created an event" }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try EventDraftArguments(arguments)
        let draft = CalendarEventDraft(
            title: args.title,
            startDate: try ToolDates.parse(args.start),
            endDate: try ToolDates.parse(args.end),
            isAllDay: args.isAllDay,
            location: args.location.isEmpty ? nil : args.location,
            notes: args.notes.isEmpty ? nil : args.notes
        )
        try await writing.create(draft)
        return "Created \"\(args.title)\"."
    }
}

struct UpdateEventTool: CoachTool {
    let reading: any CalendarReading
    let writing: any CalendarWriting
    let name = "update_event"
    let description = "Change an existing event's title, time, or details. Requires user confirmation."
    let requiresConfirmation = true
    var parameters: GenerationSchema { UpdateArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Updated an event" }

    func confirmationPreview(_ arguments: GeneratedContent) async -> [String] {
        guard let args = try? UpdateArguments(arguments),
              let id = UUID(uuidString: args.id),
              let current = try? await reading.snapshot(id: id)
        else { return ["Update an event"] }
        return [
            "Now: \(eventLine(current))",
            "Becomes: \(args.title), \(args.start) to \(args.end)",
        ]
    }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try UpdateArguments(arguments)
        guard let id = UUID(uuidString: args.id),
              let current = try await reading.snapshot(id: id) else {
            return "No event with that id. Use ids exactly as get_events reported them."
        }
        if current.isRecurring {
            return "That event is part of a recurring series, which I can't edit. Ask the user to change the series in their calendar app."
        }
        let draft = CalendarEventDraft(
            title: args.title,
            startDate: try ToolDates.parse(args.start),
            endDate: try ToolDates.parse(args.end),
            isAllDay: args.isAllDay,
            location: args.location.isEmpty ? nil : args.location,
            notes: args.notes.isEmpty ? nil : args.notes
        )
        try await writing.update(id: id, with: draft)
        return "Updated \"\(args.title)\"."
    }
}

struct DeleteEventTool: CoachTool {
    let reading: any CalendarReading
    let writing: any CalendarWriting
    let name = "delete_event"
    let description = "Delete an event. Requires user confirmation."
    let requiresConfirmation = true
    var parameters: GenerationSchema { DeleteArguments.generationSchema }

    func summary(_ arguments: GeneratedContent) -> String { "Deleted an event" }

    func confirmationPreview(_ arguments: GeneratedContent) async -> [String] {
        guard let args = try? DeleteArguments(arguments),
              let id = UUID(uuidString: args.id),
              let current = try? await reading.snapshot(id: id)
        else { return ["Delete an event"] }
        return ["Delete: \(eventLine(current))"]
    }

    func call(_ arguments: GeneratedContent) async throws -> String {
        let args = try DeleteArguments(arguments)
        guard let id = UUID(uuidString: args.id),
              let current = try await reading.snapshot(id: id) else {
            return "No event with that id. Use ids exactly as get_events reported them."
        }
        if current.isRecurring {
            return "That event is part of a recurring series, which I can't delete. Ask the user to remove the series in their calendar app."
        }
        try await writing.delete(id: id)
        return "Deleted \"\(current.title)\"."
    }
}
