import SwiftUI
import Persistence

/// Which flavor of `EventSheet` is on screen. `Identifiable` so RootView can
/// drive it with `.sheet(item:)`, the same idiom `DayDetailSheet` uses for
/// `today.detail`; a stable `id` keeps the enum from re-identifying itself
/// (and resetting the form) across the reloads a save triggers.
enum EventSheetPresentation: Identifiable {
    case create
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
        case .create:
            let start = Self.nextFullHour()
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
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditing, !isRecurring {
                    Section {
                        Button("Delete event", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
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

    /// End clamped to at least 15 minutes after start on save; a user who
    /// drags end before start gets corrected silently rather than blocked.
    private var draft: CalendarEventDraft {
        CalendarEventDraft(
            title: title,
            startDate: startDate,
            endDate: max(endDate, startDate.addingTimeInterval(15 * 60)),
            isAllDay: isAllDay,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes
        )
    }

    /// Create's default start: the next full hour, so a fresh event never
    /// lands mid-hour regardless of when "+ Add event" was tapped.
    private static func nextFullHour(from date: Date = .now, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let thisHour = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .hour, value: 1, to: thisHour) ?? date
    }
}

#Preview("Create") {
    EventSheet(mode: .create, onSave: { _ in }, onDelete: {})
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
