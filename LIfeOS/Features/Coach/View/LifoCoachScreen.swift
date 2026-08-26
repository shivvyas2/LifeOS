import SwiftUI
import DesignSystem

/// Voice-first coach. Named LIFO, never a borrowed doctor persona.
/// The globe is the listening body; the keyboard is the way in when speech is
/// not available or not wanted.
struct LifoCoachScreen: View {
    @Bindable var model: CoachViewModel
    var onDismiss: () -> Void
    /// The aurora backdrop is dark in both appearances, so every token on
    /// this screen resolves dark regardless of the system scheme.
    private let scheme: ColorScheme = .dark
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typingFocused: Bool
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ZStack {
                SlateAurora().ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 12)

                    GlassGlobe(intensity: model.level, isActive: model.phase == .listening || model.phase == .thinking)
                        .frame(width: 240, height: 240)
                        .padding(.bottom, 28)
                        .allowsHitTesting(false)

                    Text(headline)
                        .font(LifeOSType.screenTitle.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .padding(.horizontal, 28)
                        .fixedSize(horizontal: false, vertical: true)

                    if !bodyCopy.isEmpty {
                        Text(bodyCopy)
                            .font(LifeOSType.secondary)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }

                    statusPill
                        .padding(.top, 18)

                    if model.isTyping {
                        typingField
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 8)

                    controls
                        .padding(.horizontal, 36)
                        .padding(.bottom, 28)
                }
            }
            .navigationTitle("LIFO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .environment(\.colorScheme, .dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) {
                        Image(systemName: "chevron.left")
                            .font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock")
                            .font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.history.isEmpty)
                    .opacity(model.history.isEmpty ? 0.35 : 1)
                    .accessibilityLabel("History")
                }
            }
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .onChange(of: model.isTyping) { _, typing in
            if typing { typingFocused = true }
        }
        .sheet(isPresented: $showHistory) {
            historySheet
        }
    }

    private func close() {
        model.disappear()
        onDismiss()
        dismiss()
    }

    private var headline: String {
        switch model.phase {
        case .idle, .listening:
            return "Hello, how can we support your health today?"
        case .thinking:
            return "Looking at your numbers…"
        case .answered:
            return model.answer
        }
    }

    private var bodyCopy: String {
        if model.phase == .listening, !model.liveTranscript.isEmpty {
            return model.liveTranscript
        }
        if let error = model.error, model.phase != .answered {
            return error
        }
        return ""
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            Image(systemName: model.phase == .listening ? "waveform" : "message.fill")
                .font(LifeOSType.label.weight(.semibold))
            Text(model.status)
                .font(LifeOSType.label)
                .lineLimit(2)
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.5), lineWidth: 1)
        }
        .padding(.horizontal, 28)
    }

    private var typingField: some View {
        HStack(spacing: 10) {
            TextField("Ask LIFO…", text: $model.draft, axis: .vertical)
                .font(LifeOSType.secondary)
                .focused($typingFocused)
                .autocorrectionDisabled()
                .writingToolsBehavior(.disabled)
                .lineLimit(1...4)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Button {
                Task { await model.sendTyped() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(LifeOSType.screenTitle.weight(.regular))
                    .foregroundStyle(LifeOSTokens.fabFill.resolve(scheme))
            }
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.5), lineWidth: 1)
                }
        )
        .onAppear { typingFocused = true }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            GlassCircleButton(systemImage: "clock", size: 52) { showHistory = true }
                .accessibilityLabel("History")

            GlassCircleButton(
                systemImage: model.phase == .listening ? "pause.fill" : "mic.fill",
                size: 72,
                emphasized: true
            ) {
                Task { await model.toggleListening() }
            }
            .accessibilityLabel(model.phase == .listening ? "Pause" : "Listen")

            GlassCircleButton(systemImage: "keyboard", size: 52) {
                model.showKeyboard()
            }
            .accessibilityLabel("Type")
        }
    }

    private var historySheet: some View {
        NavigationStack {
            List(model.history) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.question)
                        .font(LifeOSType.label.weight(.semibold))
                    Text(turn.answer)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Earlier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
