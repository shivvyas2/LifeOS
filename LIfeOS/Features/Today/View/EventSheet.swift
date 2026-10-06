import SwiftUI
import DesignSystem
import Persistence

/// Which flavor of `EventSheet` is on screen. `Identifiable` so RootView can
/// drive it with `.sheet(item:)`, the same `.sheet(item:)` idiom the shell uses elsewhere; a stable `id` keeps the enum from re-identifying itself
/// (and resetting the form) across the reloads a save triggers.
enum EventSheetPresentation: Identifiable {
    /// `on` is the day to open the pickers on, for the callers that have one:
    /// the assistant's agenda card creates under the day being looked at, and
    /// a new event there landing on today would be the wrong day every time
    /// the card is showing any other. Nil means the next full hour from now,
    /// which is what a plain "add event" has always meant.
    case create(on: Date?)
    case edit(CalendarEventSnapshot)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let event): event.id.uuidString
        }
    }
}

/// Create or edit one calendar event. A pure function of `mode`: every write
/// goes out through `onSave`/`onDelete` rather than touching `CalendarSync`
/// directly, which is what keeps this previewable without EventKit or a
/// store.
///
/// A recurring occurrence renders read-only — fields disabled, Save and
/// Delete both hidden — because editing just one occurrence needs series
/// semantics this phase does not implement (spec S17); pointing the user at
/// the calendar app is honest, where silently mutating the occurrence would
/// not be.
struct EventSheet: View {
    let mode: EventSheetPresentation
    let onSave: (CalendarEventDraft) -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var location: String
    @State private var notes: String

    private let isRecurring: Bool
    private let isEditing: Bool

    init(mode: EventSheetPresentation, onSave: @escaping (CalendarEventDraft) -> Void, onDelete: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete

        switch mode {
        case .create(let day):
            let start = Self.nextFullHour(on: day)
            _title = State(initialValue: "")
            _isAllDay = State(initialValue: false)
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: start.addingTimeInterval(3600))
            _location = State(initialValue: "")
            _notes = State(initialValue: "")
            isRecurring = false
            isEditing = false
        case .edit(let event):
            _title = State(initialValue: event.title)
            _isAllDay = State(initialValue: event.isAllDay)
            _startDate = State(initialValue: event.startDate)
            _endDate = State(initialValue: event.endDate)
            _location = State(initialValue: event.location ?? "")
            _notes = State(initialValue: event.notes ?? "")
            isRecurring = event.isRecurring
            isEditing = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Toggle("All-day", isOn: $isAllDay)
                }
                .disabled(isRecurring)

                Section {
                    DatePicker("Starts", selection: $startDate, displayedComponents: dateComponents)
                    DatePicker("Ends", selection: $endDate, displayedComponents: dateComponents)
                }
                .disabled(isRecurring)

                Section {
                    TextField("Location", text: $location)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                .disabled(isRecurring)

                if isRecurring {
                    Section {
                        Text("This repeats. Edit the series in your calendar app.")
                            .font(LifeOSType.label.weight(.regular))
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditing, !isRecurring {
                    Section {
                        Button("Delete event", role: .destructive) {
                            confirmsDelete = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LifeOSTokens.canvas.resolve(scheme))
            .tint(LifeOSTokens.accent)
            .confirmationDialog("Delete this event?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete event", role: .destructive) { onDelete(); dismiss() }
            }
            .navigationTitle(isEditing ? "Event" : "New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !isRecurring {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(draft)
                            dismiss()
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var dateComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// End clamped on save so a user who drags end before start gets
    /// corrected silently rather than blocked. A timed event floors at 15
    /// minutes; an all-day event only floors at `startDate` itself, since
    /// end == start is its normal single-day shape and a 15-minute floor
    /// would falsify it into a timed-looking span.
    private var draft: CalendarEventDraft {
        let clampedEnd = isAllDay
            ? max(endDate, startDate)
            : max(endDate, startDate.addingTimeInterval(15 * 60))
        return CalendarEventDraft(
            title: title,
            startDate: startDate,
            endDate: clampedEnd,
            isAllDay: isAllDay,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes
        )
    }

    /// Create's default start: the next full hour, so a fresh event never
    /// lands mid-hour regardless of when "+ Add event" was tapped, on `day`
    /// when one is given.
    ///
    /// A day other than today gets 9am rather than the current clock time
    /// carried across: "next Tuesday at 16:41" is nobody's intent, and the
    /// hour someone happens to be holding the phone at says nothing about a
    /// day they are not in yet.
    private static func nextFullHour(
        on day: Date? = nil, from date: Date = .now, calendar: Calendar = .current
    ) -> Date {
        guard let day, !calendar.isDate(day, inSameDayAs: date) else {
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            let thisHour = calendar.date(from: components) ?? date
            return calendar.date(byAdding: .hour, value: 1, to: thisHour) ?? date
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}

#Preview("Create") {
    EventSheet(mode: .create(on: nil), onSave: { _ in }, onDelete: {})
}

#Preview("Edit") {
    let now = Date.now
    EventSheet(
        mode: .edit(CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "1",
            calendarTitle: "Work", title: "Design review",
            startDate: now, endDate: now.addingTimeInterval(3600),
            isAllDay: false, isRecurring: false,
            location: "Conference room B", notes: "Bring the deck"
        )),
        onSave: { _ in },
        onDelete: {}
    )
}

#Preview("Recurring") {
    let now = Date.now
    EventSheet(
        mode: .edit(CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "2",
            calendarTitle: "Work", title: "Standup",
            startDate: now, endDate: now.addingTimeInterval(30 * 60),
            isAllDay: false, isRecurring: true,
            location: nil, notes: nil
        )),
        onSave: { _ in },
        onDelete: {}
    )
}
