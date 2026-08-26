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
                    if !history.observations.isEmpty { observations(history) }
                    if !history.months.isEmpty { trend(history) }
                    if let latest = history.months.last, !latest.evidenceRows.isEmpty {
                        reasoning(latest)
                    }
                    if !visibleTracks(history).isEmpty { answers(history) }
                    if !history.notes.isEmpty { notes(history) }
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

    // MARK: - Bands

    /// `value: nil` renders `PastelFillCard`'s own em dash, so a sector never
    /// closed reads the same here as it does on the board.
    private func header(_ history: SectorHistory) -> some View {
        PastelFillCard(
            icon: SectorPalette.icon(sector),
            hue: SectorPalette.hue(sector),
            label: sector.title,
            value: history.months.last.map { String($0.userScore) },
            unit: history.months.last == nil ? nil : "/10",
            caption: history.months.last.map {
                $0.month.formatted(.dateTime.month(.wide).year())
            }
        )
    }

    /// The state every sector starts in on a fresh install: no month closed
    /// yet, so there is nothing to plot, reason about, or list answers for.
    private var emptyState: some View {
        SoftCard {
            Text("Close a month on the board to start this sector's history.")
                .font(LifeOSType.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private func observations(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Observations").font(LifeOSType.secondary).foregroundStyle(.secondary)
                ForEach(history.observations, id: \.self) { observation in
                    Text(observation).font(LifeOSType.secondary)
                }
            }
        }
    }

    /// `baseline: .windowMinimum` is correct here, not `.zero`: a sector
    /// score is a rating on a 0...10 scale, never a count building up from
    /// nought, which is exactly the case `Baseline.windowMinimum`'s own doc
    /// describes for body weight. Under it a flat year draws as steady
    /// half-height bars and a real swing draws as one; under `.zero`,
    /// `RoundedBarChart.fraction` divides by the window's own peak, so a
    /// flat year of 4s and a flat year of 9s both draw as full-height bars,
    /// indistinguishable from each other. The absolute value is carried by
    /// the header numeral, not by bar height.
    private func trend(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Trend").font(LifeOSType.secondary).foregroundStyle(.secondary)
                RoundedBarChart(
                    bars: history.months.map {
                        RoundedBarChart.Bar(
                            id: $0.month,
                            label: $0.month.formatted(.dateTime.month(.narrow)),
                            value: Double($0.userScore)
                        )
                    },
                    hue: SectorPalette.hue(sector),
                    baseline: .windowMinimum,
                    height: 120
                )
            }
        }
    }

    /// Renders the archived rows verbatim, label left, value right. Frozen at
    /// close time, so a goal changed later cannot rewrite what an earlier
    /// month's reasoning said.
    private func reasoning(_ entry: MonthEntry) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Why \(entry.month.formatted(.dateTime.month(.wide)))")
                    .font(LifeOSType.secondary).foregroundStyle(.secondary)
                ForEach(entry.evidenceRows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value).foregroundStyle(.secondary)
                    }
                    .font(LifeOSType.secondary)
                }
            }
        }
    }

    /// A track qualifies for `history.questions` on any answer across all
    /// twelve fetched months, but this band only ever renders the last
    /// `answerWindow` of them, so a track last answered outside that window
    /// is filtered here rather than rendering its prompt over bare em dashes.
    private func visibleTracks(_ history: SectorHistory) -> [QuestionTrack] {
        history.questions.filter { $0.hasAnswer(inLastMonths: answerWindow) }
    }

    /// One row per question, the last six months across it, oldest to newest,
    /// horizontally scrollable. An unanswered month renders an em dash,
    /// matching how the board shows an unscored sector: never a blank or a
    /// zero.
    private func answers(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Answers over time").font(LifeOSType.secondary).foregroundStyle(.secondary)
                ForEach(visibleTracks(history), id: \.questionID) { track in
                    questionTrackRow(track, months: history.months)
                }
            }
        }
    }

    private func questionTrackRow(_ track: QuestionTrack, months: [MonthEntry]) -> some View {
        let entries: [MonthAnswer] = Array(zip(months, track.answers).suffix(answerWindow))
            .map { MonthAnswer(month: $0.0.month, answer: $0.1) }
        return VStack(alignment: .leading, spacing: Space.half) {
            Text(track.prompt).font(LifeOSType.label.weight(.regular))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x1) {
                    ForEach(entries) { entry in
                        VStack(spacing: Space.half) {
                            Text(entry.month.formatted(.dateTime.month(.narrow)))
                                .font(LifeOSType.caption).foregroundStyle(.secondary)
                            Text(entry.answer ?? "—").font(LifeOSType.secondary)
                        }
                    }
                }
            }
        }
    }

    /// One month's answer to one question track, packaged so `ForEach` can
    /// iterate a plain `Identifiable` array instead of a tuple.
    private struct MonthAnswer: Identifiable {
        let month: Date
        let answer: String?
        var id: Date { month }
    }

    private func notes(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Notes").font(LifeOSType.secondary).foregroundStyle(.secondary)
                ForEach(Array(history.notes.enumerated()), id: \.offset) { _, note in
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(note.month.formatted(.dateTime.month(.wide).year()))
                            .font(LifeOSType.caption).foregroundStyle(.secondary)
                        Text(note.text).font(LifeOSType.secondary)
                    }
                }
            }
        }
    }

    private func openTabRow(_ action: @escaping () -> Void) -> some View {
        SoftCard {
            Button(action: action) {
                Text("Open \(sector.title)")
                    .font(LifeOSType.secondary.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
