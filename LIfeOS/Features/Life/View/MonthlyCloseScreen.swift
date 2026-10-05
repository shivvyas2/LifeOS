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
                EditorialMasthead(eyebrow: "Close \(monthName) · \(model.position) of \(model.total)",
                                  title: sector.title)

                if !model.questions.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        ForEach(model.questions, id: \.id) { question in
                            CheckInQuestionView(
                                question: question,
                                answer: model.answers[question.id],
                                onAnswer: { model.answer(question, with: $0) }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialFigure(label: "Proposed",
                                    value: model.proposed.map(String.init) ?? "—",
                                    unit: model.proposed == nil ? nil : "/10",
                                    size: 48)
                    if model.evidence.rows.isEmpty {
                        EditorialTag("No evidence yet")
                    } else {
                        ForEach(model.evidence.rows, id: \.label) { row in
                            EditorialRow(row.label.capitalized, value: row.value)
                        }
                    }
                }
                .editorialCard()

                if let note = model.note {
                    Text(note)
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let previous = model.previousUserScore {
                    Text("Last month you said \(previous).")
                        .font(LifeOSType.label.weight(.regular))
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
        .navigationTitle("")
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

    private var monthName: String { month.formatted(.dateTime.month(.wide)) }

    private var doneView: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            EditorialMasthead(eyebrow: "Life",
                              title: "Month closed",
                              detail: "Every sector you scored this pass is on the board.")
            Button("Done") {
                onFinish()
                dismiss()
            }
            .buttonStyle(.editorial(.primary, fullWidth: true))
            Spacer()
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }
}
