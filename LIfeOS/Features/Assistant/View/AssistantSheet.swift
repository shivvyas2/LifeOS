import SwiftUI
import DesignSystem
import Insights
import Persistence

/// The calendar assistant: masthead, prompt rows, the conversation, inline
/// confirmation cards, composer. A pure function of the view model's state,
/// on paper, in the same pieces LIFO uses.
struct AssistantSheet: View {
    @State var model: AssistantViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composing: Bool
    /// Raised by a tap on an agenda card's row or its Add. The same sheet
    /// Today uses, so an event edited from a conversation and one edited from
    /// the day view are edited in one place.
    @State private var eventSheet: EventSheetPresentation?

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.modelAvailable {
                    Spacer()
                    Text("The assistant needs Apple Intelligence, which isn't available on this device.")
                        .font(LifeOSType.secondary)
                        .foregroundStyle(quiet)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.x4)
                    Spacer()
                } else {
                    conversation
                    // The empty state carries the connect button, but a
                    // conversation with history hides that state; someone
                    // who revoked access later still needs a way back in.
                    if !model.isAuthorized, !model.messages.isEmpty {
                        HStack(spacing: Space.x1) {
                            Text("Calendar not connected").font(LifeOSType.secondary).foregroundStyle(quiet)
                            Spacer()
                            Button("Connect") { Task { await model.connectCalendar() } }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                        }
                        .padding(.horizontal, Space.x2)
                        .padding(.bottom, Space.half)
                    }
                    ChatComposer(text: Bindable(model).draft, placeholder: "Ask about your calendar…",
                                 isSending: model.isThinking, focus: $composing,
                                 onSend: { Task { await model.send() } })
                        .padding(.horizontal, Space.x2)
                        .padding(.bottom, 12)
                }
            }
            // The same cap LIFO uses: full screen on an iPad is not a reason
            // for a question to run the width of the room.
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .background(paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CalendarScreen(assistant: model,
                                       onTapEvent: { eventSheet = .edit($0) },
                                       onAddEvent: { eventSheet = .create(on: $0) },
                                       isCalendarConnected: model.isAuthorized,
                                       onConnectCalendar: { Task { await model.connectCalendar() } })
                    } label: { Label("Schedule", systemImage: "calendar") }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
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
        .tint(ink)
        .task { await model.appear() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.x3) {
                    masthead
                    if model.messages.isEmpty { emptyState }
                    ForEach(model.messages) { message in
                        bubble(message).id(message.id)
                    }
                    ForEach(model.pending) { write in
                        ChatConfirmation(lines: write.preview,
                                         onConfirm: { model.confirm(write.id) },
                                         onCancel: { model.cancel(write.id) })
                            .id(write.id)
                    }
                    if model.isThinking && model.pending.isEmpty {
                        ChatThinking()
                    }
                }
                .padding(.horizontal, Space.x2)
                .padding(.top, Space.x1)
                .padding(.bottom, Space.x2)
            }
            .scrollDismissesKeyboard(.interactively)
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

    private var masthead: some View {
        let headline = AssistantHeadline.make(connected: model.isAuthorized)
        return EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
    }

    /// Before the first question: the one action when there is no calendar,
    /// three prompt rows when there is.
    @ViewBuilder private var emptyState: some View {
        if !model.isAuthorized {
            Button("Connect calendar") { Task { await model.connectCalendar() } }
                .buttonStyle(.editorial(.primary))
        } else {
            VStack(spacing: 0) {
                ForEach(["What's on my calendar today?", "Find a free hour tomorrow", "Show my schedule for this week"], id: \.self) { prompt in
                    Button { model.draft = prompt; composing = true } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: Space.x1) {
                                Text(prompt).font(LifeOSType.secondary).foregroundStyle(ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: Space.x1)
                                Image(systemName: "arrow.up.left").font(LifeOSType.caption.weight(.semibold))
                                    .foregroundStyle(quiet)
                            }
                            .padding(.vertical, 14)
                            Hairline()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Puts this question in the composer")
                }
            }
        }
    }

    /// The most recent thing the assistant said. It always carries an agenda
    /// card, even when the turn called no tool: a reply about the schedule
    /// that draws no schedule is the text-only answer this screen was
    /// changed to stop producing. Older replies keep a card only if they
    /// actually touched events.
    private var latestAssistantID: UUID? {
        model.messages.last { $0.role == .assistant }?.id
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessageSnapshot) -> some View {
        switch message.role {
        case .user: ChatQuestion(message.text)
        default: assistantReply(message)
        }
    }

    private func assistantReply(_ message: ChatMessageSnapshot) -> some View {
        let touched = model.eventsByMessage[message.id] ?? []
        let drawsAgenda = model.isAuthorized
            && (!touched.isEmpty || message.id == latestAssistantID)

        return VStack(alignment: .leading, spacing: Space.x1) {
            CoachResponseView(text: message.text)
            if drawsAgenda {
                AssistantAgendaCard(
                    touched: touched,
                    events: { model.events(on: $0) },
                    onTapEvent: { eventSheet = .edit($0) },
                    onAddEvent: { eventSheet = .create(on: $0) }
                )
            }
            if !message.toolSummaries.isEmpty {
                ChatToolTags(message.toolSummaries)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
