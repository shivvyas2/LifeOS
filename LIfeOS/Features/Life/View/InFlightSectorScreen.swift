import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

/// What a sector's month still has left in it.
///
/// Three parts, in the order the questions come: where it stands and where it
/// can get to, what moves it most, and, for a sector scored from answers, the
/// questions themselves.
struct InFlightSectorScreen: View {
    let sector: LifeSector

    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @State private var model: InFlightSectorViewModel

    init(sector: LifeSector) {
        self.sector = sector
        _model = State(initialValue: InFlightSectorViewModel(sector: sector))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "\(sector.title) · In flight",
                                  title: rangeText,
                                  detail: model.remainingDays == 1 ? "1 day left" : "\(model.remainingDays) days left")

                if model.band?.ceiling == nil, sector == .money {
                    Text("No ceiling until you set budget buckets. Nothing in the data says what a good remaining spend would be.")
                        .font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }

                ForEach(Array(sections.enumerated()), id: \.element) { offset, section in
                    VStack(alignment: .leading, spacing: Space.x2) {
                        EditorialSectionHeader(index: offset + 1, title: section.title)
                        content(section)
                    }
                }

                if model.usesDefaultTargets {
                    Text("This ceiling uses the default targets. Set your own in Health to make it yours.")
                        .font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle(sector.title)
        .onAppear {
            model.attach(context)
            model.load()
        }
        .onDisappear { model.flushPendingSaves() }
    }

    private var rangeText: String {
        model.band?.rangeText ?? "Not read yet"
    }

    private enum Section: Hashable {
        case levers, questions, floor, ceiling

        var title: String {
            switch self {
            case .levers: "What moves it most"
            case .questions: "Read it now"
            case .floor: "If nothing changes"
            case .ceiling: "If you finish at your targets"
            }
        }
    }

    private var sections: [Section] {
        var list: [Section] = []
        if !model.levers.isEmpty { list.append(.levers) }
        if !model.questions.isEmpty { list.append(.questions) }
        if let band = model.band, !band.floorEvidence.isEmpty {
            list.append(.floor)
            if band.ceiling != nil { list.append(.ceiling) }
        }
        return list
    }

    @ViewBuilder
    private func content(_ section: Section) -> some View {
        switch section {
        case .levers:
            ForEach(model.levers) { delta in
                EditorialRow(delta.lever.label,
                             value: delta.delta < 0.05 ? "at target" : "+\(delta.delta.formatted(.number.precision(.fractionLength(1))))")
            }
        case .questions:
            ForEach(model.questions, id: \.id) { question in
                CheckInQuestionView(
                    question: question,
                    answer: model.answers[question.id],
                    onAnswer: { model.answer(question, with: $0) }
                )
            }
        case .floor:
            if let band = model.band { evidenceRows(band.floorEvidence) }
        case .ceiling:
            if let band = model.band { evidenceRows(band.ceilingEvidence) }
        }
    }

    @ViewBuilder
    private func evidenceRows(_ evidence: Evidence) -> some View {
        ForEach(evidence.rows, id: \.label) { row in
            EditorialRow(row.label, value: row.value)
        }
    }
}
