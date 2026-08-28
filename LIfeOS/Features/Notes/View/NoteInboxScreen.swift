import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// The notes tab on a phone.
///
/// Inbox first, not Library first. The complaint this answers is that writing
/// one line used to cost four taps: the tab, a shelf, the New menu, a page
/// kind. Here the composer is already on screen and Return keeps you in the
/// stream, so five thoughts are five sentences rather than five navigations.
///
/// Unlike `NotesSidebar`, which argues against `List` for good reasons, this
/// screen uses one: swipe to file and swipe to archive are the interaction the
/// stream is built around, `swipeActions` exists only on `List` rows, and
/// hand-rolling drag gestures to avoid the container would be more code and
/// worse behaviour than styling it away.
struct NoteInboxScreen: View {
    @Bindable var model: NoteInboxViewModel
    /// The library's own model, needed for the pushed Library screen and for
    /// the shelves a swipe files into.
    @Bindable var library: NotesViewModel
    var onOpen: (UUID) -> Void
    var onOpenLibrary: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @FocusState private var composerFocused: Bool
    /// `.sheet(item:)` needs `Identifiable` and `UUID` is not, so the page
    /// being filed is carried in a wrapper rather than raw.
    @State private var filing: FilingTarget?

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            chips
            rows
            composer
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Library", systemImage: "sidebar.left", action: onOpenLibrary)
            }
        }
        .sheet(item: $filing) { target in
            FilingSheet(snapshot: library.snapshot) { bucket, folderID in
                model.file(target.id, to: bucket, folderID: folderID)
                filing = nil
            }
        }
    }

    /// The page a swipe is filing. See `filing` above for why this exists.
    private struct FilingTarget: Identifiable {
        let id: UUID
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x1) {
                ForEach(NoteStreamChip.rowOrder) { chip in
                    let isOn = model.chip == chip
                    Button { model.chip = chip } label: {
                        Text(chip.title)
                            .font(LifeOSType.label.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? LifeOSTokens.canvas.resolve(scheme) : primary)
                            .padding(.horizontal, Space.x2)
                            .padding(.vertical, Space.half)
                            .background(
                                Capsule().fill(isOn ? primary : primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.vertical, Space.x1)
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch model.stream {
        case .cards(let cards):
            if cards.isEmpty {
                empty
            } else {
                List {
                    ForEach(cards) { card in
                        StreamRow(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(card.id) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                Button("File", systemImage: "tray.and.arrow.down") {
                                    filing = FilingTarget(id: card.id)
                                }
                                .tint(LifeOSTokens.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Archive", systemImage: "archivebox", role: .destructive) {
                                    model.archive(card.id)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

        case .tasks(let tasks):
            if tasks.isEmpty {
                empty
            } else {
                List {
                    ForEach(tasks, id: \.id) { task in
                        TaskRow(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(task.documentID) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Space.half) {
            Spacer()
            Text(emptyLine)
                .font(LifeOSType.secondary)
                .foregroundStyle(secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Each chip's blank state says what would fill it, rather than all three
    /// saying "Nothing here".
    private var emptyLine: String {
        switch model.chip {
        case .inbox: "Nothing waiting. Write something below."
        case .all:   "No pages yet."
        case .todos: "No open to-dos."
        }
    }

    private var composer: some View {
        HStack(spacing: Space.x1) {
            Button {
                model.isTodo.toggle()
            } label: {
                Image(systemName: model.isTodo ? "checkmark.square.fill" : "square")
                    .foregroundStyle(model.isTodo ? LifeOSTokens.accent : secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isTodo ? "Capturing as a to-do" : "Capture as a to-do")

            TextField("Write something", text: $model.draft, axis: .vertical)
                .font(LifeOSType.body)
                .foregroundStyle(primary)
                .focused($composerFocused)
                .lineLimit(1...4)
                .onSubmit(submit)
                .submitLabel(.return)

            // A vertical-axis TextField treats Return from the software
            // keyboard as a newline rather than a submit, so `onSubmit` above
            // never fires from it; a visible send button, shown once there is
            // something to send, is the control that actually works on a
            // phone. Follows `LifoCoachScreen`'s composer, which solves the
            // same problem the same way. `onSubmit` stays wired for a
            // hardware keyboard's Return key.
            if !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(LifeOSType.label.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LifeOSTokens.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                // A sketch has nothing to type, so it makes a page holding a
                // sketch block and opens it rather than going through the
                // draft, which would file a paragraph saying "Sketch".
                if let id = model.captureSketch() { onOpen(id) }
            } label: {
                Image(systemName: "scribble")
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New sketch")
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.draft.isEmpty)
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, Space.x1)
        .background(
            LifeOSTokens.canvas.resolve(scheme)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Shared by the send button and `onSubmit`. Refocuses the field after a
    /// successful capture, so writing five thoughts in a row is five
    /// sentences rather than five re-taps of the field; a failed capture
    /// (an empty draft) leaves focus alone.
    private func submit() {
        if model.capture() != nil { composerFocused = true }
    }
}

/// One page in the stream: what it is, what it says, and how far its to-dos
/// have got.
private struct StreamRow: View {
    let card: NoteCardSnapshot

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            Text(card.icon.isEmpty ? "\u{1F4C4}" : card.icon)
                .font(LifeOSType.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title.isEmpty ? "Untitled" : card.title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .lineLimit(1)

                if !card.excerpt.isEmpty {
                    Text(card.excerpt)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .lineLimit(1)
                }

                HStack(spacing: Space.x1) {
                    if let folder = card.folderName {
                        Text(folder)
                    }
                    if card.taskCount > 0 {
                        Text("\(card.doneCount)/\(card.taskCount)")
                            .monospacedDigit()
                    }
                }
                .font(LifeOSType.caption)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(.vertical, Space.half)
    }
}

/// One to-do, with the page it came from. The page matters: a to-do with no
/// context is a reminder, and this is not a reminders app.
private struct TaskRow: View {
    let task: NoteTask

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            Image(systemName: task.isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

            Text(task.text.isEmpty ? "Untitled to-do" : task.text)
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .lineLimit(2)
        }
        .padding(.vertical, Space.half)
    }
}

/// Where a swiped page goes. Shelves and their folders, nothing else: the
/// person's own collections arrive with the phase that builds them.
private struct FilingSheet: View {
    let snapshot: NotesSnapshot
    let onPick: (NoteBucket, UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(NoteBucket.allCases.filter { $0 != .archive }) { bucket in
                    Section(bucket.title) {
                        Button("On \(bucket.title)") { onPick(bucket, nil) }
                        ForEach(snapshot.folders(in: bucket)) { folder in
                            Button(folder.name) { onPick(bucket, folder.id) }
                        }
                    }
                }
            }
            .navigationTitle("File")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
