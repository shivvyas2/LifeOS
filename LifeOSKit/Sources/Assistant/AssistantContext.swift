// LifeOSKit/Sources/Assistant/AssistantContext.swift
import Foundation
import Insights
import Persistence

public enum CalendarAssistant {
    /// The six tools, or none: with no authorized source the model gets no
    /// calendar tools and the instructions say so, so it explains what to
    /// connect rather than calling something that would fail.
    public static func tools(
        reading: any CalendarReading,
        writing: any CalendarWriting,
        collector: CalendarEventCollector? = nil
    ) -> [any CoachTool] {
        [
            GetEventsTool(reading: reading, collector: collector),
            FindFreeTimeTool(reading: reading),
            AnalyzeScheduleTool(reading: reading),
            CreateEventTool(writing: writing, collector: collector),
            UpdateEventTool(reading: reading, writing: writing),
            DeleteEventTool(reading: reading, writing: writing),
        ]
    }

    public static func instructions(authorized: Bool) -> String {
        let base = """
        You are a calendar assistant. Resolve relative dates against the
        stated current time. Never invent an event id; use ids exactly as
        get_events reports them. State times in the user's timezone. Keep
        replies to a sentence or two. Ask before assuming a duration.
        """
        guard authorized else {
            return base + """


            There are no calendar tools available because no calendar is
            connected. Tell the user to connect their calendar from this
            screen before you can read or change events.
            """
        }
        return base
    }

    /// Today and tomorrow inline, so "what's on today?" needs no tool call:
    /// the cheapest path and the most reliable one on a small model.
    public static func contextPrefix(
        now: Date,
        timeZone: TimeZone,
        today: [CalendarEventSnapshot],
        tomorrow: [CalendarEventSnapshot]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        // Foundation normalizes TimeZone(identifier: "UTC") to the identifier
        // "GMT", so a caller who explicitly asked for UTC would otherwise see
        // it silently relabeled. They're equivalent for calendar display, so
        // print the label the caller reached for.
        let label = timeZone.identifier == "GMT" ? "UTC" : timeZone.identifier
        let todayLines = today.isEmpty
            ? "Today: nothing scheduled"
            : "Today:\n" + today.map { eventLine($0, timeZone: timeZone) }.joined(separator: "\n")
        let tomorrowLines = tomorrow.isEmpty
            ? "Tomorrow: nothing scheduled"
            : "Tomorrow:\n" + tomorrow.map { eventLine($0, timeZone: timeZone) }.joined(separator: "\n")
        return """
        Current time: \(formatter.string(from: now)) (\(label))
        \(todayLines)
        \(tomorrowLines)
        """
    }
}
