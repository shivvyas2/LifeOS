#if DEBUG
import SwiftUI
import SwiftData
import Persistence
import DesignSystem

/// In-memory design fixtures; never writes to an account or syncs sample pages.
struct NotesDesignPreview: View {
    var showEditor = false
    var showsPreviewLabel = true
    /// `notes-editor-new`: a blank page with the title focused;
    /// `notes-editor`: the sample page, nothing focused;
    /// `notes-editor-picker`: its first block focused, the picker up;
    /// `notes-filing`: the sample page with the filing sheet up.
    var page: String = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fixture = NotesPreviewFixture()
    @State private var frames = WalkthroughFrames()
    /// The real driver, for `notes-walkthrough-live`, which the UI tests tap through.
    @State private var live = NotesWalkthrough()
    @State private var showsLiveHub = true

    var body: some View {
        Group {
            switch page {
            case "notes-editor-new":
                NavigationStack {
                    NoteEditorScreen(model: fixture.blankEditor, focusOnAppear: .title, onOpenLinked: { _ in })
                }
            case "notes-filing":
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, openFilingOnAppear: true, onOpenLinked: { _ in })
                }
            case "notes-editor":
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, onOpenLinked: { _ in })
                }
            case "notes-editor-picker":
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, focusOnAppear: .firstBlock, onOpenLinked: { _ in })
                }
            // `--step=N`, 1 to 5: the overlay over the shelf (1, 4, 5) or the
            // sample page with its picker up (2, 3).
            case "notes-walkthrough":
                walkthroughPage
            // The whole walkthrough, driver and all, over the fixture's shelf.
            // `--from-folder` starts it with a folder and a search showing;
            // `--start-before-hub` starts it before the hub is on screen, as a
            // replay from Settings on another tab does.
            case "notes-walkthrough-live":
                livePage
            default:
                if showEditor {
                    NavigationStack {
                        NoteEditorScreen(model: fixture.editor, onOpenLinked: { _ in })
                            .navigationTitle("Preview page")
                    }
                } else {
                    NotesHubScreen(model: fixture.notes, plan: fixture.plan, onAddHabit: {})
                }
            }
        }
        .modelContainer(fixture.container)
        .environment(\.layout, .metrics(for: sizeClass == .regular ? .regular : .compact))
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsPreviewLabel, page.isEmpty {
                Text("DESIGN PREVIEW · SAMPLE PAGES")
                    .font(.caption2).tracking(1).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(LifeOSTokens.canvas.light)
            }
        }
    }

    private var livePage: some View {
        ZStack {
            if showsLiveHub {
                NotesHubScreen(model: fixture.notes, plan: fixture.plan, onAddHabit: {})
            } else {
                LifeOSTokens.canvas.light.ignoresSafeArea()
            }
        }
        .environment(\.walkthroughFrames, live.frames)
        .environment(\.notesWalkthrough, live)
        .overlay { NotesWalkthroughLayer(walkthrough: live) }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--from-folder") {
                fixture.notes.selection = .folder(fixture.personalFolderID)
                fixture.notes.query = "weekend"
            }
            if arguments.contains("--start-before-hub") {
                showsLiveHub = false
                live.start(notes: fixture.notes)
                try? await Task.sleep(for: .milliseconds(800))
                showsLiveHub = true
            } else {
                try? await Task.sleep(for: .milliseconds(500))
                live.start(notes: fixture.notes)
            }
        }
    }

    private var step: Int {
        let raw = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--step=") }?.dropFirst(7)
        return min(max(Int(raw ?? "1") ?? 1, 1), 5)
    }

    @ViewBuilder private var walkthroughPage: some View {
        let current = WalkthroughScript.notes[step - 1]
        Group {
            if step == 2 || step == 3 {
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, focusOnAppear: .firstBlock, onOpenLinked: { _ in })
                }
            } else {
                NotesHubScreen(model: fixture.notes, plan: fixture.plan, onAddHabit: {})
            }
        }
        .environment(\.walkthroughFrames, frames)
        .overlay {
            if let frame = frames.frames[current.anchor] {
                WalkthroughOverlay(step: current, frame: frame, isLast: step == 5, onNext: {}, onSkip: {})
                    .ignoresSafeArea()
            }
        }
    }
}

@MainActor private final class NotesPreviewFixture {
    let container: ModelContainer
    let notes = NotesViewModel()
    let plan = PlanViewModel()
    let editor: NoteEditorViewModel
    let blankEditor: NoteEditorViewModel
    let personalFolderID: UUID

    init() {
        container = try! LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let store = NotesStore(context: context)
        let personal = try! store.createFolder(name: "Personal", bucket: .areas)
        personalFolderID = personal.id
        let work = try! store.createFolder(name: "Ideas & projects", bucket: .projects)
        let page = try! store.createDocument(title: "Weekend reset", bucket: .areas, folderID: personal.id,
            blocks: [
                NoteBlock(text: "A little space to think, plan, and make room for the week ahead."),
                NoteBlock(kind: .heading2, text: "Make time for"),
                NoteBlock(kind: .todo, text: "Walk somewhere new", isChecked: true),
                NoteBlock(kind: .todo, text: "Book a quiet hour to read"),
                NoteBlock(kind: .quote, text: "Keep the plan small enough to actually enjoy it."),
                NoteBlock(kind: .heading2, text: "Sketch it out"),
                NoteBlock(kind: .sketch, sketchHeight: 180)
            ])
        try! store.setIcon("📓", on: page)
        try! store.toggleFavorite(page)
        for (title, text) in [
            ("An idea worth keeping", "A small collection of things I want to try, make, and learn."),
            ("Reading list", "Books, essays, and ideas to come back to."),
            ("Plan for the week", "Choose one priority. Leave room for the unexpected."),
            ("Little things to remember", "A place for thoughts before they turn into plans.")
        ] {
            _ = try! store.createDocument(title: title, bucket: .projects, folderID: work.id,
                                          blocks: [NoteBlock(text: text)])
        }
        notes.attach(context)
        notes.load()
        plan.attach(context)
        plan.load()
        editor = NoteEditorViewModel(documentID: page.id)
        editor.attach(context)
        editor.load()
        let blank = try! store.createDocument(title: "", bucket: .projects)
        blankEditor = NoteEditorViewModel(documentID: blank.id)
        blankEditor.attach(context)
        blankEditor.load()
    }
}

#Preview("Notes library") { NotesDesignPreview() }
#Preview("Page editor") { NotesDesignPreview(showEditor: true) }
#endif
