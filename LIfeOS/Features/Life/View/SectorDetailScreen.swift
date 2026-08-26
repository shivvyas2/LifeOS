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
/// cleanly with just its header.
struct SectorDetailScreen: View {
    let sector: LifeSector
    /// Called to open the sector's full tab. Non-nil only for the three
    /// sectors that own one (Body, Money, Mission); nil hides the row, so
    /// this screen never needs to know how the tab bar works.
    let onOpenTab: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var model = SectorDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                if let history = model.history {
                    header(history)
                    if !history.observations.isEmpty { observations(history) }
                    if !history.months.isEmpty { trend(history) }
                    if let latest = history.months.last, !latest.evidenceRows.isEmpty {
                        reasoning(latest)
                    }
                    if !history.questions.isEmpty { answers(history) }
                    if !history.notes.isEmpty { notes(history) }
                    if let onOpenTab { openTabRow(onOpenTab) }
                } else {
                    ProgressView()
                }
            }
            .padding(Space.x2)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle(sector.title)
        .task {
            model.attach(context)
            model.load(sector: sector)
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

    private func observations(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Observations").font(.subheadline).foregroundStyle(.secondary)
                ForEach(history.observations, id: \.self) { observation in
                    Text(observation).font(.callout)
                }
            }
        }
    }

    /// `baseline: .zero` is correct here and its consequence is intended: the
    /// chart scales within its own window, so a flat year of 4s renders as
    /// steady half-height bars rather than a flat line at 40%. The absolute
    /// value is carried by the header numeral, not by bar height.
    private func trend(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Trend").font(.subheadline).foregroundStyle(.secondary)
                RoundedBarChart(
                    bars: history.months.map {
                        RoundedBarChart.Bar(
                            id: $0.month,
                            label: $0.month.formatted(.dateTime.month(.narrow)),
                            value: Double($0.userScore)
                        )
                    },
                    hue: SectorPalette.hue(sector),
                    baseline: .zero,
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
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(entry.evidenceRows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// One row per question, the last six months across it, oldest to newest,
    /// horizontally scrollable. An unanswered month renders an em dash,
    /// matching how the board shows an unscored sector: never a blank or a
    /// zero.
    private func answers(_ history: SectorHistory) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Answers over time").font(.subheadline).foregroundStyle(.secondary)
                ForEach(history.questions, id: \.questionID) { track in
                    questionTrackRow(track, months: history.months)
                }
            }
        }
    }

    private func questionTrackRow(_ track: QuestionTrack, months: [MonthEntry]) -> some View {
        let entries: [MonthAnswer] = Array(zip(months, track.answers).suffix(6))
            .map { MonthAnswer(month: $0.0.month, answer: $0.1) }
        return VStack(alignment: .leading, spacing: Space.half) {
            Text(track.prompt).font(.footnote)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x1) {
                    ForEach(entries) { entry in
                        VStack(spacing: Space.half) {
                            Text(entry.month.formatted(.dateTime.month(.narrow)))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(entry.answer ?? "—").font(.callout)
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
                Text("Notes").font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(history.notes.enumerated()), id: \.offset) { _, note in
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(note.month.formatted(.dateTime.month(.wide).year()))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(note.text).font(.callout)
                    }
                }
            }
        }
    }

    private func openTabRow(_ action: @escaping () -> Void) -> some View {
        SoftCard {
            Button(action: action) {
                Text("Open \(sector.title)")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
