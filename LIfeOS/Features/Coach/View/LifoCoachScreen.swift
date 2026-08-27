import SwiftUI
import DesignSystem

/// The coach. Text first, voice second.
///
/// It was voice-first, with a 240pt globe holding the top of the screen and a
/// keyboard tucked behind a button. That inverted the actual usage: most
/// questions are typed, most of the time, and a screen that opens on a
/// microphone asks someone to speak out loud before it asks them anything
/// else. Now the field is the subject of the screen and the mic sits beside
/// it, one tap away, for when speaking is easier.
struct LifoCoachScreen: View {
    @Bindable var model: CoachViewModel
    var onDismiss: () -> Void

    /// The aura is dark in both appearances, so every token here resolves
    /// dark regardless of the system scheme.
    private let scheme: ColorScheme = .dark
    @FocusState private var typingFocused: Bool
    @State private var showHistory = false

    var body: some View {
        ZStack {
            LifoAura(intensity: model.level,
                     isActive: model.phase == .listening || model.phase == .thinking)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.history.isEmpty && model.answer.isEmpty {
                            opening
                        } else {
                            transcript
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                composer
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory) { historySheet }
        .task { model.appear() }
        .onDisappear { model.disappear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LIFO")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LifoPalette.ink)
                Text("Your life, answered from your own data.")
                    .font(.system(size: 13))
                    .foregroundStyle(LifoPalette.quietInk)
            }
            Spacer(minLength: 12)

            if !model.history.isEmpty {
                Button { showHistory = true } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LifoPalette.quietInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel("History")
            }

            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LifoPalette.quietInk)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Opening

    private var opening: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 40)

            Text("How can I help you?")
                .font(.system(size: 32, weight: .semibold, design: .serif))
                .foregroundStyle(LifoPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Suggestions, not a menu: they are the questions this app can
            // actually answer well, phrased the way someone would say them,
            // so the first use is not a blank field and a guess about scope.
            FlowChips(items: Self.suggestions) { prompt in
                model.draft = prompt
                Task { await model.sendTyped() }
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(LifoPalette.ink.opacity(0.85))
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Deliberately about this person's own data, because that is what the
    /// coach is scoped to. A suggestion it would decline teaches the wrong
    /// thing about what it is for.
    private static let suggestions = [
        "How did I sleep this week?",
        "Where did my money go?",
        "What should I fix first?",
        "Am I saving enough?",
        "How is my recovery trending?",
    ]

    // MARK: - Transcript

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(model.history) { turn in
                turnView(question: turn.question, answer: turn.answer)
            }

            if model.phase == .thinking {
                if !model.liveTranscript.isEmpty {
                    bubble(model.liveTranscript, isQuestion: true)
                }
                HStack(spacing: 8) {
                    ProgressView().tint(LifoPalette.ink)
                    Text("Thinking…")
                        .font(.system(size: 13))
                        .foregroundStyle(LifoPalette.quietInk)
                }
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(LifoPalette.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func turnView(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            bubble(question, isQuestion: true)
            Text(answer)
                .font(.system(size: 16))
                .foregroundStyle(LifoPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func bubble(_ text: String, isQuestion: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(LifoPalette.ink)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(Capsule().fill(.ultraThinMaterial))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Composer

    /// The field is the primary control and the mic is beside it. The send
    /// button only appears once there is something to send, so the resting
    /// state is a field and one small microphone rather than a row of icons.
    private var composer: some View {
        VStack(spacing: 10) {
            if model.phase == .listening {
                Text(model.liveTranscript.isEmpty ? "Listening…" : model.liveTranscript)
                    .font(.system(size: 13))
                    .foregroundStyle(LifoPalette.quietInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Ask anything about your life…", text: $model.draft, axis: .vertical)
                        .font(.system(size: 16))
                        .focused($typingFocused)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                        .foregroundStyle(LifoPalette.ink)
                        .tint(LifoPalette.cyan)
                        .onSubmit { Task { await model.sendTyped() } }

                    if !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task { await model.sendTyped() }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(LifoPalette.night)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(LifoPalette.cyan))
                        }
                        .accessibilityLabel("Send")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                )

                Button {
                    Task { await model.toggleListening() }
                } label: {
                    Image(systemName: model.phase == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.phase == .listening ? LifoPalette.night : LifoPalette.ink)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(model.phase == .listening
                                          ? AnyShapeStyle(LifoPalette.cyan)
                                          : AnyShapeStyle(.ultraThinMaterial))
                        )
                }
                .accessibilityLabel(model.phase == .listening ? "Stop listening" : "Speak instead")
            }
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.draft.isEmpty)
        }
        .padding(.bottom, 14)
    }

    private func close() {
        model.disappear()
        onDismiss()
    }

    private var historySheet: some View {
        NavigationStack {
            List(model.history) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.question).font(.system(size: 14, weight: .semibold))
                    Text(turn.answer).font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Earlier")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Chips that wrap onto as many rows as they need.
///
/// `LazyVGrid` cannot do this: its columns are fixed widths, and these are
/// sentences of very different lengths. Laying them out by hand is the only
/// way they pack tightly without a column grid's ragged gaps.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LifoPalette.ink)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                }
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrapping layout: place each subview on the current row until it
/// does not fit, then start another.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
