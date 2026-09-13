#if DEBUG
import SwiftUI
import SwiftData
import Persistence
import DesignSystem

/// In-memory design fixtures; never writes to an account or syncs sample pages.
struct NotesDesignPreview: View {
    var showEditor = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fixture = NotesPreviewFixture()

    var body: some View {
        Group {
            if showEditor {
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, onOpenLinked: { _ in })
                        .navigationTitle("Preview page")
                }
            } else {
                NotesHubScreen(model: fixture.notes, plan: fixture.plan, onAddHabit: {})
            }
        }
        .modelContainer(fixture.container)
        .environment(\.layout, .metrics(for: sizeClass == .regular ? .regular : .compact))
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("DESIGN PREVIEW · SAMPLE PAGES")
                .font(.caption2).tracking(1).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(LifeOSTokens.canvas.light)
        }
    }
}

@MainActor private final class NotesPreviewFixture {
    let container: ModelContainer
    let notes = NotesViewModel()
    let plan = PlanViewModel()
    let editor: NoteEditorViewModel

    init() {
        container = try! LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let store = NotesStore(context: context)
        let personal = try! store.createFolder(name: "Personal", bucket: .areas)
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
    }
}

#Preview("Notes library") { NotesDesignPreview() }
#Preview("Page editor") { NotesDesignPreview(showEditor: true) }
#endif
