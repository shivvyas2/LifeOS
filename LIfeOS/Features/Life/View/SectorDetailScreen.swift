import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

/// One sector's history, in four bands: the trend, the reasoning frozen at
/// close time, every answer laid across the months, and the free-text notes.
///
/// A pure function of `SectorDetailViewModel`, like `LifeBoardScreen`: the
/// view model fetches and maps, `SectorHistory.build` decides everything, and
/// this screen only renders what it is handed. A band with nothing to show is
/// omitted rather than rendered empty, so a sector never closed still renders
/// cleanly with just its header and a one-line nudge to close a month.
struct SectorDetailScreen: View {
    let sector: LifeSector
    /// Called to open the sector's full tab. Non-nil only for the three
    /// sectors that own one (Body, Money, Mission); nil hides the row, so
    /// this screen never needs to know how the tab bar works.
    let onOpenTab: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = SectorDetailViewModel()

    /// How many recent months the answers band renders. Shared with
    /// `QuestionTrack.hasAnswer(inLastMonths:)` so a track that qualifies
    /// for `history.questions` but has nothing inside this window is
    /// filtered out rather than rendered as a prompt over bare em dashes.
    private let answerWindow = 6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                if let history = model.history {
                    header(history)
                    if history.months.isEmpty { emptyState }
                    ForEach(Array(sections(history).enumerated()), id: \.element) { offset, section in
                        VStack(alignment: .leading, spacing: Space.x2) {
                            EditorialSectionHeader(index: offset + 1, title: section.title)
                            content(section, history: history)
                        }
                    }
                    if let onOpenTab { openTabRow(onOpenTab) }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.leading, layout.railInset)
            .padding(.top, Space.x3)
            .padding(.bottom, layout.contentBottomInset)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle(sector.title)
        .task {
            model.attach(context)
            model.load(sector: sector)
        }
        // Matches `RootView.reloadAll()`'s `scenePhase == .active` refresh on
        // every other surface, so this screen does not go stale across a
        // background/foreground cycle while it happens to be on screen.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.load(sector: sector) }
        }
    }

    // MARK: - Sections

    /// The bands in order, only those with something to show, so the index
    /// numbers run without gaps.
    private enum Section: Hashable {
        case observations, trend, reasoning, answers, notes

        var title: String {
            switch self {
            case .observations: "Observations"
            case .trend: "Trend"
            case .reasoning: "Why"
            case .answers: "Answers over time"
            case .notes: "Notes"
            }
        }
    }

    private func sections(_ history: SectorHistory) -> [Section] {
        var list: [Section] = []
        if !history.observations.isEmpty { list.append(.observations) }
        if !history.months.isEmpty { list.append(.trend) }
        if let latest = history.months.last, !latest.evidenceRows.isEmpty { list.append(.reasoning) }
        if !visibleTracks(history).isEmpty { list.append(.answers) }
        if !history.notes.isEmpty { list.append(.notes) }
        return list
    }

    @ViewBuilder
    private func content(_ section: Section, history: SectorHistory) -> some View {
        switch section {
        case .observations:
            ForEach(history.observations, id: \.self) { observation in
                Text(observation).font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
        case .trend:
            trend(history)
        case .reasoning:
            if let latest = history.months.last {
                Text("Why \(latest.month.formatted(.dateTime.month(.wide)))").editorialEyebrow()
                ForEach(latest.evidenceRows, id: \.label) { row in
                    EditorialRow(row.label, value: row.value)
                }
            }
        case .answers:
            ForEach(visibleTracks(history), id: \.questionID) { track in
                questionTrackRow(track, months: history.months)
            }
        case .notes:
            ForEach(Array(history.notes.enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(note.month.formatted(.dateTime.month(.wide).year())).editorialEyebrow()
                    Text(note.text).font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Hairline()
                }
            }
        }
    }

    /// The screen's one field: the score, the month it belongs to, the icon.
    private func header(_ history: SectorHistory) -> some View {
        let latest = history.months.last
        return EditorialField(.dusk) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(latest.map { "\(sector.title) · \($0.month.formatted(.dateTime.month(.wide).year()))" } ?? sector.title)
                        .editorialEyebrow()
                    EditorialFigure(label: "Score",
                                    value: latest.map { String($0.userScore) } ?? "—",
                                    unit: latest == nil ? nil : "/10")
                }
                Spacer(minLength: Space.x1)
                Image(systemName: SectorPalette.icon(sector))
                    .font(LifeOSType.sectionTitle)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The state every sector starts in on a fresh install: no month closed
    /// yet, so there is nothing to plot, reason about, or list answers for.
    private var emptyState: some View {
        Text("Close a month on the board to start this sector's history.")
            .font(LifeOSType.secondary)
            .editorialCard()
    }

    /// `baseline: .windowMinimum`, not `.zero`: a sector score is a rating on
    /// a 0...10 scale, never a count building up from nought. The absolute
    /// value is carried by the header figure, not by bar height.
    private func trend(_ history: SectorHistory) -> some View {
        RoundedBarChart(
            bars: history.months.map {
                RoundedBarChart.Bar(
                    id: $0.month,
                    label: $0.month.formatted(.dateTime.month(.narrow)),
                    value: Double($0.userScore)
                )
            },
            style: .ink,
            baseline: .windowMinimum,
            height: 120
        )
    }

    /// A track qualifies for `history.questions` on any answer across all
    /// twelve fetched months, but this band only ever renders the last
    /// `answerWindow` of them.
    private func visibleTracks(_ history: SectorHistory) -> [QuestionTrack] {
        history.questions.filter { $0.hasAnswer(inLastMonths: answerWindow) }
    }

    private func questionTrackRow(_ track: QuestionTrack, months: [MonthEntry]) -> some View {
        let entries: [MonthAnswer] = Array(zip(months, track.answers).suffix(answerWindow))
            .map { MonthAnswer(month: $0.0.month, answer: $0.1) }
        return VStack(alignment: .leading, spacing: Space.half) {
            Text(track.prompt).font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(entries) { entry in
                        VStack(spacing: Space.half) {
                            Text(entry.month.formatted(.dateTime.month(.narrow))).editorialEyebrow()
                            Text(entry.answer ?? "—").font(LifeOSType.secondary)
                                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        }
                    }
                }
            }
            Hairline()
        }
    }

    /// One month's answer to one question track, packaged so `ForEach` can
    /// iterate a plain `Identifiable` array instead of a tuple.
    private struct MonthAnswer: Identifiable {
        let month: Date
        let answer: String?
        var id: Date { month }
    }

    private func openTabRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("Open \(sector.title)")
                Spacer()
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(.editorial(.secondary, fullWidth: true))
    }
}
