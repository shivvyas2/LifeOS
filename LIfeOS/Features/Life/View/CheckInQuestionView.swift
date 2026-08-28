import SwiftUI
import DesignSystem
import Persistence
import Sectors

/// One check-in question and its answer.
///
/// Free of any view model so both surfaces that ask these questions can use
/// it: the monthly close, and a sector card in flight. `AnswerPersistence`
/// still decides when an answer is written; this only reports it.
struct CheckInQuestionView: View {
    let question: CheckInQuestion
    let answer: String?
    let onAnswer: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(question.prompt)
                .font(LifeOSType.secondary.weight(.medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            if question.isFreeText {
                TextField("", text: Binding(
                    get: { answer ?? "" },
                    set: { onAnswer($0) }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                VStack(spacing: Space.half) {
                    ForEach(question.options, id: \.label) { option in
                        Button {
                            onAnswer(option.label)
                        } label: {
                            Text(option.label)
                                .font(LifeOSType.label)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            answer == option.label
                                ? LifeOSTokens.accent
                                : LifeOSTokens.secondaryText.resolve(scheme)
                        )
                    }
                }
            }
        }
    }
}
