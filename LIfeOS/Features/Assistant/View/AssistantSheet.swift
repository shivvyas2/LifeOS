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
    /// Raised by a tap on an agenda card's row or its plus. The same sheet
    /// Today uses, so an event edited from a conversation and one edited from
    /// the day view are edited in one place.
    @State private var eventSheet: EventSheetPresentation?

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
                                    .font(LifeOSType.label.weight(.regular))
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
        .sheet(item: $eventSheet) { mode in
            EventSheet(
                mode: mode,
                onSave: { draft in
                    let id: UUID? = if case .edit(let event) = mode { event.id } else { nil }
                    Task { await model.save(draft, editing: id) }
                },
                onDelete: {
                    guard case .edit(let event) = mode else { return }
                    Task { await model.delete(id: event.id) }
                }
            )
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

    /// The most recent thing LIFO said. It always carries an agenda card, even
    /// when the turn called no tool: a reply about the schedule that draws no
    /// schedule is the text-only answer this screen was changed to stop
    /// producing. Older replies keep a card only if they actually touched
    /// events, so scrolling back through twenty turns is not twenty week
    /// strips.
    private var latestAssistantID: UUID? {
        model.messages.last { $0.role == .assistant }?.id
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessageSnapshot) -> some View {
        switch message.role {
        case .user: userBubble(message)
        default: assistantReply(message)
        }
    }

    /// Still a bubble, and deliberately: the question is a transcript entry,
    /// and the one thing it must do is not compete with the answer under it.
    private func userBubble(_ message: ChatMessageSnapshot) -> some View {
        Text(message.text)
            .font(LifeOSType.secondary)
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LifeOSTokens.fabFill.resolve(scheme).opacity(0.15))
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func assistantReply(_ message: ChatMessageSnapshot) -> some View {
        let touched = model.eventsByMessage[message.id] ?? []
        let drawsAgenda = model.isAuthorized
            && (!touched.isEmpty || message.id == latestAssistantID)

        return VStack(alignment: .leading, spacing: 8) {
            InsightCallout(text: message.text)

            // The events the turn was about, drawn rather than left for the
            // sentence above to describe.
            if drawsAgenda {
                AssistantAgendaCard(
                    touched: touched,
                    events: { model.events(on: $0) },
                    onTapEvent: { eventSheet = .edit($0) },
                    onAddEvent: { eventSheet = .create(on: $0) }
                )
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
