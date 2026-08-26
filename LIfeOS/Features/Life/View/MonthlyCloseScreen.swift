import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

/// Walks the nine sectors of one month's close, one at a time.
///
/// Sheet-presented from `LifeBoardScreen`'s banner, so unlike the board
/// itself this screen owns its view model rather than having one handed in
/// by `RootView`: nothing above the sheet needs the close's state once the
/// sheet is dismissed, and every other consumer of `LifeSector` state
/// (the board) reloads from the store on `onFinish` instead of sharing this
/// instance.
struct MonthlyCloseScreen: View {
    let month: Date
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var model: MonthlyCloseViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model, let sector = model.sector {
                    sectorView(sector, model: model)
                } else {
                    doneView
                }
            }
        }
        .task {
            guard model == nil else { return }
            let created = MonthlyCloseViewModel(context: context, month: month)
            model = created
            created.advance()
        }
    }

    @ViewBuilder
    private func sectorView(_ sector: LifeSector, model: MonthlyCloseViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                header(sector)

                if !model.questions.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        ForEach(model.questions, id: \.id) { question in
                            questionView(question, model: model)
                        }
                    }
                }

                // `value: nil` renders PastelFillCard's own em dash, which is
                // exactly right for a sector with no evidence: not scored
                // badly, not scored at all.
                PastelFillCard(
                    icon: SectorPalette.icon(sector),
                    hue: SectorPalette.hue(sector),
                    label: "Proposed",
                    value: model.proposed.map(String.init),
                    caption: model.evidence.isEmpty ? "NO EVIDENCE YET" : nil,
                    captionColor: LifeOSTokens.secondaryText.resolve(scheme)
                )

                if !model.evidence.rows.isEmpty {
                    VStack(alignment: .leading, spacing: Space.half) {
                        ForEach(model.evidence.rows, id: \.label) { row in
                            HStack {
                                Text(row.label.capitalized)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                Spacer()
                                Text(row.value)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            }
                        }
                    }
                }

                if let note = model.note {
                    Text(note)
                        .font(.system(size: 14))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let previous = model.previousUserScore {
                    Text("Last month you said \(previous).")
                        .font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                VStack(alignment: .leading, spacing: Space.x1) {
                    HeroNumeral(value: String(model.chosenScore), unit: "/ 10", label: "Your score")
                    Stepper(
                        "Adjust your score",
                        value: Binding(
                            get: { model.chosenScore },
                            set: { model.setChosenScore($0) }
                        ),
                        in: 0...10
                    )
                    .labelsHidden()
                }
                .padding(.top, Space.x1)
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("\(model.position) of \(model.total)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { model.skip() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { model.commit() }
            }
        }
    }

    @ViewBuilder
    private func header(_ sector: LifeSector) -> some View {
        HStack(spacing: Space.x2) {
            Image(systemName: SectorPalette.icon(sector))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 44, height: 44)
                .background(Circle().fill(LifeOSTokens.cardSurface.resolve(scheme)))

            Text(sector.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        }
    }

    @ViewBuilder
    private func questionView(_ question: CheckInQuestion, model: MonthlyCloseViewModel) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(question.prompt)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            if question.isFreeText {
                TextField("", text: Binding(
                    get: { model.answers[question.id] ?? "" },
                    set: { model.answer(question, with: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                VStack(spacing: Space.half) {
                    ForEach(question.options, id: \.label) { option in
                        Button {
                            model.answer(question, with: option.label)
                        } label: {
                            Text(option.label)
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            model.answers[question.id] == option.label
                                ? LifeOSTokens.accent
                                : LifeOSTokens.secondaryText.resolve(scheme)
                        )
                    }
                }
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: Space.x2) {
            Text("Month closed")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text("Every sector you scored this pass is on the board.")
                .font(.system(size: 14))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .multilineTextAlignment(.center)
            PrimaryButton("Done") {
                onFinish()
                dismiss()
            }
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }
}
