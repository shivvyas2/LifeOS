#if DEBUG
import SwiftUI
import SwiftData
import Persistence
import DesignSystem

/// Isolated sample data for Xcode design previews. No provider access or account writes.
struct CalendarHealthDesignPreview: View {
    @State private var fixture = CalendarHealthFixture()
    @State private var page = 0
    @State private var metric = TodayMetric.steps
    @State private var section = HealthSection.health
    @State private var date = Date()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            Text("DESIGN PREVIEW · SAMPLE DATA").font(.caption2).tracking(1).padding(.top, 6)
            UnderlinePicker(selection: $page, options: [(0, "Calendar"), (1, "Health"), (2, "History")])
                .padding(.horizontal)
            NavigationStack {
                if page == 0 {
                    MonthScreen()
                } else if page == 1 {
                    HealthHubScreen(activity: ActivitySnapshot(steps: 8240, exerciseMinutes: 35, activeEnergyKcal: 460),
                                    weight: BodySnapshot(weightKg: 77.4, weeklyDeltaKg: 0.2),
                                    recovery: fixture.recovery, wellness: WellnessSnapshot(),
                                    onSelectMetric: { metric = $0; page = 2 }, section: $section, selectedDate: $date)
                } else {
                    MetricDetailScreen(metric: metric, model: fixture.metric).id(metric)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Menu("Metric") { ForEach(TodayMetric.allCases) { item in
                                Button(item.title) { metric = item }
                            } }
                        } }
                }
            }
        }
        .modelContainer(fixture.container)
        .environment(\.layout, .metrics(for: sizeClass == .regular ? .regular : .compact))
    }
}

@MainActor private final class CalendarHealthFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let metric = MetricDetailViewModel()
    let recovery = RecoverySnapshot(recoveryPct: 82, hrvMs: 62, restingHR: 54, sleepMinutes: 432,
        sleepPerformancePct: 89, sleepEfficiencyPct: 92, sleepConsistencyPct: 84, sleepDebtMinutes: 18,
        nights: [SleepComposition(date: .now, lightMinutes: 220, remMinutes: 112, swsMinutes: 100, awakeMinutes: 18)])

    init() {
        let calendar = Calendar.current
        let context = container.mainContext
        let store = MetricsStore(context: context)
        for offset in 0..<30 where offset != 3 && offset != 8 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now)!
            try! store.upsert(date: date) { row in
                row.steps = 8240 + (offset % 4) * 730
                row.sleepMinutes = 432 + (offset % 3) * 15
                row.weightKg = 77.4 + Double(offset % 5) * 0.1
                row.whoopRecoveryPct = 82 - Double(offset % 5) * 4
            }
        }
        for (hour, title) in [(9, "A little time to focus"), (13, "Lunch with Maya"), (18, "Evening walk")] {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
            let event = CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: title,
                calendarTitle: "Personal", title: title, startDate: start, endDate: start.addingTimeInterval(3600),
                isAllDay: false, isRecurring: false, location: hour == 13 ? "Corner café" : nil, notes: nil)
            context.insert(CalendarEvent(from: event))
        }
        try! context.save()
        metric.attach(context)
    }
}

#Preview { CalendarHealthDesignPreview() }
#endif
