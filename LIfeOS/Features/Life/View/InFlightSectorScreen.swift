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
                bandHeader

                if !model.levers.isEmpty {
                    section("What moves it most") {
                        ForEach(model.levers) { delta in
                            HStack {
                                Text(delta.lever.label)
                                Spacer()
                                Text(delta.delta < 0.05 ? "at target" : "+\(delta.delta, specifier: "%.1f")")
                                    .monospacedDigit()
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            }
                            .font(LifeOSType.secondary)
                        }
                    }
                }

                if !model.questions.isEmpty {
                    section("Read it now") {
                        ForEach(model.questions, id: \.id) { question in
                            CheckInQuestionView(
                                question: question,
                                answer: model.answers[question.id],
                                onAnswer: { model.answer(question, with: $0) }
                            )
                        }
                    }
                }

                if let band = model.band, band.floorEvidence.isEmpty == false {
                    section("If nothing changes") {
                        evidenceRows(band.floorEvidence)
                    }
                    if band.ceiling != nil {
                        section("If you finish at your targets") {
                            evidenceRows(band.ceilingEvidence)
                        }
                    }
                }

                if model.usesDefaultTargets {
                    Text("This ceiling uses the default targets. Set your own in Health to make it yours.")
                        .font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
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

    @ViewBuilder
    private var bandHeader: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(rangeText)
                .font(LifeOSType.display)
                .monospacedDigit()
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text(model.remainingDays == 1 ? "1 day left" : "\(model.remainingDays) days left")
                .font(LifeOSType.secondary.weight(.medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            if model.band?.ceiling == nil, sector == .money {
                Text("No ceiling until you set budget buckets. Nothing in the data says what a good remaining spend would be.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
    }

    private var rangeText: String {
        model.band?.rangeText ?? "Not read yet"
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title)
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            content()
        }
    }

    @ViewBuilder
    private func evidenceRows(_ evidence: Evidence) -> some View {
        ForEach(evidence.rows, id: \.label) { row in
            HStack {
                Text(row.label)
                Spacer()
                Text(row.value)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .font(LifeOSType.secondary)
        }
    }
}
