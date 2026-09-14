#if DEBUG && LAUNCH_FILM_PREVIEW
import SwiftUI
import DesignSystem
import Persistence

/// Isolated, synthetic screen captures for the launch film. Never a production entry point.
struct LaunchFilmPreview: View {
    private var page: String { ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--page=") }?.dropFirst(7).description ?? "cat" }
    var body: some View {
        Group {
            switch page {
            case "notes": NotesDesignPreview(showEditor: false, showsPreviewLabel: false)
            case "today": NavigationStack {
                TodayScreen(snapshot: today, onSelectDay: { _ in }, onConnectCalendar: {}, onAddEvent: {}, onTapEvent: { _ in }, onOpenToday: {}, isHealthConnected: true)
                    .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            }
            case "money": NavigationStack {
                MoneyScreen(snapshot: .init(income: 5200, expenses: 2840, net: 2360, savingsRate: 0.454, netWorth: 18420,
                    recent: [.init(id: UUID(), merchant: "Corner Coffee", category: "Food & drink", amount: -6.50, date: .now, pending: false), .init(id: UUID(), merchant: "Fresh Market", category: "Groceries", amount: -64.20, date: .now, pending: false)],
                    monthLabel: "September", isConnected: true, hasConnectedBank: true, lastSyncedAt: .now))
                    .navigationTitle("Money").navigationBarTitleDisplayMode(.inline)
            }
            default:
                ZStack {
                    Color(red: 0.969, green: 0.957, blue: 0.929).ignoresSafeArea()
                    VStack(spacing: 0) {
                        Text("A little company.").font(.system(size: 34, weight: .semibold)).padding(.top, 65)
                        OnboardingCat(page: 0, isActive: true).frame(height: 480)
                        Text("For your everyday.").font(.system(size: 24)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .environment(\.layout, .metrics(for: .compact))
        .preferredColorScheme(.light)
    }
    private var today: TodaySnapshot {
        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let cells: [DotCell] = (0..<35).map { index in
            let date = (2..<32).contains(index) ? cal.date(byAdding: .day, value: index - 2, to: first) : nil
            if index == 15 { return DotCell(id: index, date: date, state: .today) }
            if index < 15 && index >= 2 { return DotCell(id: index, date: date, state: .onTarget) }
            return DotCell(id: index, date: date, state: .future)
        }
        let start = cal.date(byAdding: .hour, value: 8, to: cal.startOfDay(for: .now))!
        let event = CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: "launch-demo", calendarTitle: "Personal", title: "A walk before work", startDate: start, endDate: start.addingTimeInterval(3600), isAllDay: false, isRecurring: false, location: nil, notes: nil)
        return TodaySnapshot(date: cal.date(byAdding: .day, value: 13, to: first)!, cells: cells, streak: 6, steps: 8240, stepsProgress: 1.03, sleepMinutes: 452, sleepProgress: 0.94, weightKg: 77.4, recoveryPct: 82, calendarAccess: .authorized, agenda: [event])
    }
}
#endif
