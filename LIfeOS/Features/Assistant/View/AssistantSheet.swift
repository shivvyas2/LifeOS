import SwiftUI
import DesignSystem
import Insights
import Persistence

/// The calendar assistant: message list, activity chips, inline confirmation
/// cards, composer. A pure function of the view model's state.
struct AssistantSheet: View {
    @State var model: AssistantViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    if !model.modelAvailable {
                        Spacer()
                        Text("The assistant needs Apple Intelligence, which isn't available on this device.")
                            .font(LifeOSType.secondary)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    } else {
                        conversation
                        // The empty state carries the connect button, but a
                        // conversation with history hides that state; someone
                        // who revoked access later still needs a way back in.
                        if !model.isAuthorized, !model.messages.isEmpty {
                            HStack(spacing: 10) {
                                Text("Calendar not connected")
                                    .font(.system(size: 13))
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                Spacer()
                                CapsuleButton(title: "Connect") {
                                    Task { await model.connectCalendar() }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                        }
                        composer
                    }
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.appear() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        emptyState.padding(.top, 48)
                    }
                    ForEach(model.messages) { message in
                        bubble(message).id(message.id)
                    }
                    ForEach(model.pending) { write in
                        confirmationCard(write).id(write.id)
                    }
                    if model.isThinking && model.pending.isEmpty {
                        Text("Thinking…")
                            .font(LifeOSType.label.weight(.regular))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
                .padding(16)
            }
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: model.pending.count) {
                if let last = model.pending.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(model.isAuthorized
                 ? "Ask about your schedule, or tell me to move something."
                 : "Connect your calendar so I can see your schedule.")
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .multilineTextAlignment(.center)
            if !model.isAuthorized {
                CapsuleButton(title: "Connect calendar") {
                    Task { await model.connectCalendar() }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bubble(_ message: ChatMessageSnapshot) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user
                              ? AnyShapeStyle(LifeOSTokens.fabFill.resolve(scheme).opacity(0.15))
                              : AnyShapeStyle(.ultraThinMaterial))
                )
            if !message.toolSummaries.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.toolSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(LifeOSType.eyebrow.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func confirmationCard(_ write: PendingWrite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(write.preview, id: \.self) { line in
                Text(line)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            HStack(spacing: 14) {
                CapsuleButton(title: "Confirm", prominent: true) { model.confirm(write.id) }
                Button("Cancel") { model.cancel(write.id) }
                    .buttonStyle(.plain)
                    .font(LifeOSType.secondary.weight(.medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask about your calendar…", text: Bindable(model).draft, axis: .vertical)
                .font(LifeOSType.secondary)
                .focused($composing)
                .lineLimit(1...4)
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(LifeOSType.screenTitle.weight(.regular))
                    .foregroundStyle(LifeOSTokens.fabFill.resolve(scheme))
            }
            .disabled(model.isThinking || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
