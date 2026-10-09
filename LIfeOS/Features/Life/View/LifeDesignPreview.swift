#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

/// Fixture pages for the Life tab and the shell header, mounted by
/// `--design-preview` with `--page=life`, `life-empty`, `life-detail`,
/// `life-inflight`, `life-close` or `shell`. Six closed months are invented
/// in an in-memory store; nothing here touches the real one.
struct LifeDesignPreview: View {
    let page: String
    @State private var fixture = LifeFixture()

    var body: some View {
        Group {
            switch page {
            case "life-empty":
                LifeBoardScreen(model: fixture.emptyBoard, onOpenTab: { _ in })
                    .modelContainer(fixture.emptyContainer)
            case "life-detail":
                NavigationStack { SectorDetailScreen(sector: .body, onOpenTab: {}) }
                    .modelContainer(fixture.container)
            case "life-inflight":
                NavigationStack { InFlightSectorScreen(sector: .body) }
                    .modelContainer(fixture.container)
            case "life-close":
                // This month, not last: the fixture has already scored every
                // month before it, and a scored month has no walk to show.
                MonthlyCloseScreen(month: fixture.thisMonth)
                    .modelContainer(fixture.container)
            case "shell":
                shell
            default:
                LifeBoardScreen(model: fixture.board, onOpenTab: { _ in }, initiallyOpen: Self.openSector,
                                places: [LifePlace(title: "Notes", detail: "42 notes · 3 in inbox", systemImage: "text.book.closed") {},
                                         LifePlace(title: "Projects", detail: "2 projects · 4 tasks today", systemImage: "square.stack.3d.up") {}])
                    .modelContainer(fixture.container)
            }
        }
        .environment(\.quickActions, Self.actions)
        .environment(\.shellProfile, ShellProfile(photo: nil, open: {}))
    }

    /// A paper page under the full header, to look at the bar on its own.
    private var shell: some View {
        NavigationStack {
            ScrollView {
                EditorialMasthead(eyebrow: "Shell · Preview", title: "The header",
                                  detail: "Assistant, LIFO, Start, then you.")
                    .padding(Space.x3)
            }
            .background(LifeOSTokens.canvas.resolve(.light).ignoresSafeArea())
            .shellToolbar()
        }
    }

    /// `--open=family` mounts that card lifted.
    private static var openSector: LifeSector? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--open=") }
            .flatMap { LifeSector(rawValue: String($0.dropFirst(7))) }
    }

    static let actions: [QuickAction] = [
        QuickAction(id: "assistant", systemImage: "calendar.badge.clock", label: "Calendar assistant") {},
        QuickAction(id: "coach", systemImage: "message.fill", label: "LIFO", shortLabel: "LIFO") {},
        QuickAction(id: "beginActivity", systemImage: "plus", label: "Begin activity", isProminent: true, shortLabel: "Start") {},
    ]
}

@MainActor private final class LifeFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let emptyContainer = try! LifeOSContainer.make(inMemory: true)
    let board = LifeBoardViewModel()
    let emptyBoard = LifeBoardViewModel()
    let calendar = Calendar.current
    let lastMonth: Date
    let thisMonth: Date

    init() {
        thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))!
        lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
        seed(thisMonth: thisMonth)
        board.attach(container.mainContext)
        // Closed mode: the fixture seeds scores, not the live inputs an
        // in-flight band is read from, so that is the mode with figures.
        board.mode = .closed
        board.load()
        emptyBoard.attach(emptyContainer.mainContext)
        emptyBoard.load()
    }

    /// Six closed months per sector, with a shape in each so the trend has
    /// something to say: Body climbs, Friends dips, the rest wander.
    private func seed(thisMonth: Date) {
        let store = SectorStore(context: container.mainContext, calendar: calendar)
        let shapes: [LifeSector: [Int]] = [
            .family: [6, 6, 7, 7, 7, 8], .romance: [5, 6, 6, 7, 6, 7], .soul: [4, 5, 5, 6, 6, 6],
            .friends: [7, 7, 6, 5, 4, 3], .growth: [6, 6, 6, 7, 8, 8], .money: [5, 6, 6, 6, 7, 6],
            .mission: [6, 7, 7, 8, 8, 8], .body: [4, 5, 6, 6, 7, 8], .mind: [6, 5, 6, 6, 7, 7],
        ]
        for (sector, scores) in shapes {
            for (offset, value) in scores.enumerated() {
                let month = calendar.date(byAdding: .month, value: offset - scores.count, to: thisMonth)!
                let evidence = Evidence([
                    EvidenceRow(label: "Sleep", value: "7h 12m", normalised: 0.8),
                    EvidenceRow(label: "Exercise", value: "4 of 5 sessions", normalised: 0.8),
                ])
                let score = try! store.record(sector: sector, month: month, proposed: value, evidence: evidence)
                try! store.commit(userScore: value, to: score)
            }
        }
    }
}
#endif
