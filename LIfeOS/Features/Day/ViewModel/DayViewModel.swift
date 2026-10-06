import Foundation
import SwiftData
import AppSurfaces
import DesignSystem
import Persistence

/// Loads one day's briefing from the stores and the weather provider, and
/// writes ticks and new tasks back through the same paths the editor uses.
@MainActor @Observable
final class DayViewModel {
    private(set) var date: Date
    private(set) var briefing: DayBriefing?

    private var context: ModelContext?
    private var providers: DayProviders?
    private var sync: NoteSyncing?
    private let calendar: Calendar
    private var weatherTask: Task<Void, Never>?

    init(date: Date, calendar: Calendar = .current) {
        self.date = calendar.startOfDay(for: date)
        self.calendar = calendar
    }

    func attach(_ context: ModelContext, providers: DayProviders?, sync: NoteSyncing?) {
        self.context = context
        self.providers = providers
        self.sync = sync
    }

    var isOnToday: Bool { calendar.isDateInToday(date) }

    func step(_ days: Int) {
        guard let moved = calendar.date(byAdding: .day, value: days, to: date) else { return }
        goTo(moved)
    }

    func goToToday() { goTo(.now) }

    func goTo(_ newDate: Date) {
        date = calendar.startOfDay(for: newDate)
        load()
    }

    /// Everything but the weather, synchronously; the weather follows.
    func load() {
        guard let context else { return }
        let placement = DayPlacement.of(date, calendar: calendar)
        let sections = DaySections.visible(for: placement)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let keptWeather: WeatherState = (self.briefing?.date == date) ? (self.briefing?.weather ?? .loading) : .loading
        var briefing = DayBriefing(
            date: date, placement: placement, sections: sections,
            weather: sections.contains(.weather) ? keptWeather : .hidden,
            agenda: [], checklist: [], readings: nil, workouts: [], spend: nil, nudges: [], dayLook: nil
        )
        do {
            briefing.agenda = try CalendarStore(context: context, calendar: calendar)
                .events(from: date, to: dayEnd)
                .sorted { lhs, rhs in
                    if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                    return lhs.startDate < rhs.startDate
                }
            briefing.checklist = try loadChecklist(context: context, editable: placement.isEditable)
            if sections.contains(.readings) {
                let metrics = MetricsStore(context: context, calendar: calendar)
                let targets = try metrics.goals().targets
                let row = try metrics.metrics(from: date, to: date).first
                briefing.readings = DayReadings(
                    steps: row?.steps, stepsTarget: targets.steps,
                    sleepMinutes: row?.sleepMinutes, sleepTargetMinutes: targets.sleepMinutes,
                    weightKg: row?.weightKg, recoveryPct: row?.whoopRecoveryPct
                )
                briefing.workouts = try metrics.workouts(on: date).map {
                    DayWorkout(id: $0.externalID, title: $0.activityName, durationMinutes: $0.durationMinutes)
                }
            }
            if sections.contains(.money) {
                let entries = try MoneyStore(context: context, calendar: calendar).entries(from: date, to: date)
                    .filter(\.isSpending)
                let rows = entries.sorted { abs($0.amount) > abs($1.amount) }.prefix(3)
                    .map { DaySpendRow(id: $0.id, merchant: $0.merchant, amount: $0.amount) }
                briefing.spend = DaySpending(total: -entries.map(\.amount).reduce(0, +), rows: Array(rows))
            }
            if sections.contains(.nudges) {
                let key = WeatherCache.dayKey(date, calendar: calendar)
                briefing.nudges = PushService.shared.entries.filter { $0.day == key }
                    .sorted { $0.receivedAt < $1.receivedAt }
            }
        } catch {
            assertionFailure("Day load failed: \(error)")
        }
        briefing.dayLook = dayLook(for: briefing)
        self.briefing = briefing
        if sections.contains(.weather) { loadWeather() }
    }

    private func loadChecklist(context: ModelContext, editable: Bool) throws -> [ChecklistRow] {
        let notes = NotesStore(context: context, calendar: calendar)
        let plan = PlanStore(context: context, calendar: calendar)
        let journal = try notes.journalEntryIfPresent(on: date)
        let due = try notes.tasks(dueOn: date).compactMap { task -> DayChecklist.DueTask? in
            guard let page = try? notes.document(id: task.documentID), !page.isArchived else { return nil }
            return DayChecklist.DueTask(documentID: task.documentID, blockID: task.id, text: task.text,
                                        isChecked: task.isChecked, pageTitle: page.displayTitle)
        }
        let habits = try plan.entries(kind: .habit).map { entry in
            DayChecklist.Habit(id: entry.id, title: entry.title, createdAt: entry.createdAt,
                               streak: (try? plan.streak(for: entry, endingOn: date)) ?? 0)
        }
        return DayChecklist.rows(
            journal: journal?.blocks ?? [], journalID: journal?.id, due: due, habits: habits,
            ticked: try plan.tickedHabitIDs(on: date), day: date, editable: editable, calendar: calendar
        )
    }

    private func dayLook(for briefing: DayBriefing) -> String? {
        let weather: DayLookText.Weather? = if case .ready(let forecast) = briefing.weather {
            DayLookText.Weather(conditionSymbol: forecast.conditionSymbol, feelsLikeHighC: forecast.feelsLikeHighC,
                                rainChanceByHour: forecast.rainChanceByHour)
        } else { nil }
        let due = briefing.checklist.filter { if case .page = $0.source { return !$0.isDone } else { return false } }.count
        return DayLookText.sentence(
            weather: weather, agendaCount: briefing.agenda.count,
            firstStart: briefing.agenda.first { !$0.isAllDay }?.startDate, dueCount: due,
            currentHour: isOnToday ? calendar.component(.hour, from: .now) : nil, calendar: calendar
        )
    }

    // MARK: Weather

    private func loadWeather() {
        guard let providers else { setWeather(.unavailable); return }
        let cache = WeatherCache()
        if let cached = cache.forecast(for: date, calendar: calendar), cached.isFresh(at: .now) {
            setWeather(.ready(cached))
            return
        }
        switch providers.location.access {
        case .notDetermined: setWeather(.needsLocation); return
        case .denied: setWeather(.denied); return
        case .granted: break
        }
        if case .ready = briefing?.weather {} else { setWeather(.loading) }
        let day = date
        weatherTask?.cancel()
        weatherTask = Task {
            do {
                let location = try await providers.location.currentLocation()
                guard let forecast = try await providers.weather.forecast(for: day, at: location) else {
                    if self.date == day { setWeather(.unavailable) }
                    return
                }
                cache.store(forecast, calendar: calendar)
                if self.date == day { setWeather(.ready(forecast)) }
            } catch {
                if self.date == day { setWeather(.unavailable) }
            }
        }
    }

    private func setWeather(_ state: WeatherState) {
        guard var briefing else { return }
        briefing.weather = state
        briefing.dayLook = dayLook(for: briefing)
        self.briefing = briefing
    }

    func allowLocation() async {
        guard let providers else { return }
        _ = await providers.location.requestAccess()
        loadWeather()
    }

    // MARK: Writes

    func tick(_ row: ChecklistRow) {
        guard let context, row.isEditable else { return }
        let notes = NotesStore(context: context, calendar: calendar)
        do {
            switch row.source {
            case .journal(let blockID):
                guard let page = try notes.journalEntryIfPresent(on: date) else { return }
                try toggle(blockID, on: page, notes: notes)
            case .page(let documentID, let blockID):
                guard let page = try notes.document(id: documentID) else { return }
                try toggle(blockID, on: page, notes: notes)
            case .habit(let entryID):
                // Habits keep today's rule: a tick is a record of the day it is made.
                guard isOnToday else { return }
                let plan = PlanStore(context: context, calendar: calendar)
                guard let entry = try plan.entries(kind: .habit).first(where: { $0.id == entryID }) else { return }
                try plan.toggleTick(for: entry, on: date)
            }
        } catch {
            assertionFailure("Day tick failed: \(error)")
        }
        // `didSave` reloads the screen; nothing else to do here.
    }

    private func toggle(_ blockID: UUID, on page: NoteDocument, notes: NotesStore) throws {
        let result = NoteBlockEditor.toggleCheck(page.blocks, at: blockID)
        guard result.handled else { return }
        try notes.update(page, blocks: result.blocks)
        requestSync()
    }

    /// Appends a to-do to the day's journal page, creating the page on the
    /// first add. A page that is only its blank paragraph gets the to-do in
    /// its place rather than under it.
    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let context, !trimmed.isEmpty, briefing?.placement.isEditable == true else { return }
        let notes = NotesStore(context: context, calendar: calendar)
        do {
            let page = try notes.journalEntry(on: date)
            var blocks = page.blocks
            if blocks.count == 1, blocks[0].kind == .paragraph, blocks[0].isEmpty { blocks = [] }
            blocks.append(NoteBlock(kind: .todo, text: trimmed))
            try notes.update(page, blocks: blocks)
            requestSync()
        } catch {
            assertionFailure("Day add failed: \(error)")
        }
    }

    func journalPageID() -> UUID? {
        guard let context else { return nil }
        return try? NotesStore(context: context, calendar: calendar).journalEntryIfPresent(on: date)?.id
    }

    private func requestSync() {
        guard let sync else { return }
        Task { await sync.sync() }
    }
}
