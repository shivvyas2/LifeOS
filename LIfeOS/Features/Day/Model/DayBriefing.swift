import Foundation
import AppSurfaces
import DesignSystem
import Persistence

enum WeatherState: Equatable {
    case hidden, needsLocation, denied, loading, unavailable
    case ready(DayForecast)
}

struct DayReadings: Equatable {
    var steps: Int?
    var stepsTarget: Int
    var sleepMinutes: Int?
    var sleepTargetMinutes: Int
    var weightKg: Double?
    var recoveryPct: Double?
}

struct DaySpendRow: Identifiable, Equatable {
    let id: UUID
    let merchant: String
    let amount: Double
}

struct DaySpending: Equatable {
    let total: Double
    let rows: [DaySpendRow]
}

struct DayWorkout: Identifiable, Equatable {
    let id: String
    let title: String
    let durationMinutes: Int
}

/// Everything the day screen draws, as plain values.
struct DayBriefing: Equatable {
    let date: Date
    let placement: DayPlacement
    let sections: [DaySection]
    var weather: WeatherState
    var agenda: [CalendarEventSnapshot]
    var checklist: [ChecklistRow]
    var readings: DayReadings?
    var workouts: [DayWorkout]
    var spend: DaySpending?
    var nudges: [InboxEntry]
    var dayLook: String?

    var checklistDone: Int { checklist.filter(\.isDone).count }
}
