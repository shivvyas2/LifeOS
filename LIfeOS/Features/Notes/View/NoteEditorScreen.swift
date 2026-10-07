import SwiftUI
import DesignSystem
import Persistence

/// One page, open.
///
/// A column of blocks with an ink layer over them and, when the page is linked
/// to, a backlinks list under them. The measure is capped rather than filling an
/// iPad's width: prose at 1000 points across is unreadable, and this is the one
/// screen in the app that is genuinely prose.
struct NoteEditorScreen: View {
    @Bindable var model: NoteEditorViewModel
    /// What to focus once the page is up: the title for a page just made.
    var focusOnAppear: NoteEditorFocus = .none
    /// Previews open the filing sheet straight away to draw it.
    var openFilingOnAppear = false
    var onOpenLinked: (UUID) -> Void
    var onClose: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    /// Measured, so the ink canvas covers exactly the blocks. A canvas sized to
    /// the screen instead would clip strokes the moment the page scrolled.
    @State private var contentHeight: CGFloat = 0
    /// The editor's own width, which is not the pane's: in a three-column
    /// layout the page is the last of three, and only it knows how much it got.
    @State private var editorWidth: CGFloat = 0
    @State private var showEmojiPicker = false
    @State private var drawWithFinger = false
    @State private var confirmClearDrawing = false
    @State private var showFiling = false
    @FocusState private var titleFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    /// Backlinks move out from under the text once there is room beside it.
    /// A measure capped at 760 leaves a wide pane with empty margin, and the
    /// list of what points here is the obvious thing to put in it. Below this
    /// the panel would squeeze the writing, so it stays under the text.
    private var showsInspector: Bool {
        editorWidth >= 1_040 && !model.backlinks.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            page

            if showsInspector {
                Rectangle()
                    .fill(primary.opacity(scheme == .dark ? 0.14 : 0.07))
                    .frame(width: 1)

                backlinksInspector
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            editorWidth = width
        }
        .animation(.easeInOut(duration: 0.2), value: showsInspector)
        // On the screen, not on the header inside the scroll view, so the
        // sheet presents from the page itself.
        .sheet(isPresented: $showFiling) {
            NoteFilingSheet(
                targets: model.moveTargets(),
                currentBucket: model.isInInbox ? nil : model.bucket, currentFolderID: model.folderID,
                onPick: { model.file(to: $0.bucket, folderID: $0.folderID) },
                onCreateFolder: { model.createFolder(named: $0, in: $1) }
            )
        }
        .onAppear {
            switch focusOnAppear {
            case .title: titleFocused = true
            case .firstBlock: model.focusedBlockID = model.blocks.first?.id
            case .none: break
            }
            if openFilingOnAppear { showFiling = true }
        }
        .onChange(of: model.focusedBlockID) { _, id in
            if id != nil { titleFocused = false }
        }
        // And the other way: a tap back into the title lets the block go, or
        // the block's text view would pull the caret straight back out.
        .onChange(of: titleFocused) { _, focused in
            if focused { model.focusedBlockID = nil }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.isInking {
                    HStack {
                        Label(layout.isRegular ? "Pencil drawing" : "Drawing", systemImage: "pencil.tip")
                        Spacer()
                        if layout.isRegular {
                            Toggle("Draw with finger", isOn: $drawWithFinger).toggleStyle(.button)
                        }
                    }
                    .font(.caption).foregroundStyle(LifeOSTokens.accent)
                    .padding(.vertical, 12)
                }
                pageBody
                if !model.backlinks.isEmpty, !showsInspector { backlinks }
                Spacer(minLength: 120)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: layout.isRegular ? .center : .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.focusedBlockID != nil {
                NoteAccessoryBar(
                    slashQuery: model.slashQuery,
                    linkSuggestions: model.linkSuggestions,
                    linkQuery: model.linkQuery,
                    currentKind: focusedKind,
                    onPickBlock: { model.applySlashCommand($0) },
                    onChangeKind: { model.pickBlockKind($0) },
                    onPickLink: { model.completeLink(with: $0) },
                    onIndent: { delta in
                        if let id = model.focusedBlockID { model.indent(id, by: delta) }
                    },
                    onToggleInk: { model.isInking.toggle() },
                    isInking: model.isInking,
                    onDismissKeyboard: { model.focusedBlockID = nil }
                )
                // The whole bar, so the slash menu and the link picker that
                // take its place keep the walkthrough's step on screen.
                .walkthroughAnchor(.notesBlockPicker)
                .transition(.move(edge: .bottom))
            }
        }
        .toolbar { toolbar }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.isInking = false; model.flush() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .confirmationDialog("Clear the drawing on this page?", isPresented: $confirmClearDrawing) {
            Button("Clear drawing", role: .destructive) { model.setDrawing(nil) }
        }
        .tint(LifeOSTokens.accent)
        // Escape backs out one layer at a time rather than closing everything
        // at once: the block menu, then the link picker, then the keyboard.
        // Closing the page on the first press would lose someone mid-sentence.
        .onKeyPress(.escape) {
            if model.slashQuery != nil { model.slashQuery = nil; return .handled }
            if model.linkQuery != nil { model.linkQuery = nil; return .handled }
            if model.focusedBlockID != nil { model.focusedBlockID = nil; return .handled }
            return .ignored
        }
        .animation(.easeInOut(duration: 0.15), value: model.slashQuery)
        .animation(.easeInOut(duration: 0.15), value: model.linkQuery)
    }

    private var focusedKind: NoteBlockKind {
        guard let id = model.focusedBlockID, let index = model.index(of: id) else { return .paragraph }
        return model.blocks[index].kind
    }

    private func leaveTitle() {
        titleFocused = false
        model.submitTitle()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.icon.isEmpty {
                Button { showEmojiPicker = true } label: {
                    Text(model.icon).font(.largeTitle).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Change page icon")
            }

            TextField("Untitled", text: $model.title, axis: .vertical)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(primary)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($titleFocused)
                .submitLabel(.next)
                .onSubmit { leaveTitle() }
                // A vertical field puts Return into the text instead of
                // submitting; the editor takes the hint and moves on.
                .onChange(of: model.title) { _, title in
                    // Only a Return the person typed: a title loaded or synced
                    // with a newline in it is not an invitation to move the caret.
                    if titleFocused, title.contains(where: \.isNewline) { leaveTitle() }
                }

            metaRow
        }
        .padding(.bottom, 18)
        .sheet(isPresented: $showEmojiPicker) {
            NoteIconPicker(selected: model.icon) { model.setIcon($0) }
                .presentationDetents([.height(320)])
        }
    }

    private var metaRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { metadata }
            VStack(alignment: .leading, spacing: 8) { metadata }
        }
        .font(.caption)
        .foregroundStyle(secondary)
    }

    @ViewBuilder private var metadata: some View {
        Button { showFiling = true } label: {
            Label(model.fileLabel, systemImage: model.isInInbox ? "tray" : "folder")
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
        .accessibilityHint("Choose where this page lives")
        .walkthroughAnchor(.notesFileChip)
        if let date = model.entryDate {
            Text(date, format: .dateTime.month(.abbreviated).day())
        }
        if model.kind == .task {
            Menu {
                ForEach(PlanStatus.allCases, id: \.self) { status in
                    Button(status.title) { model.setStatus(status) }
                }
            } label: { Label(model.status.title, systemImage: "circle.dotted") }
        }
        Button { model.flush() } label: {
            Label(model.saveMessage, systemImage: model.hasSaveError ? "exclamationmark.circle" : "checkmark")
        }
        .buttonStyle(.plain)
        .disabled(!model.hasSaveError)
        .accessibilityHint(model.hasSaveError ? "Retry saving this page" : "")
    }

    // MARK: - Blocks and ink

    private var pageBody: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, block in
                    NoteBlockRow(
                        block: block,
                        index: index,
                        ordinal: model.ordinals[block.id],
                        isFocused: model.focusedBlockID == block.id,
                        onChangeText: { model.setText($0, on: block.id) },
                        onToggleCheck: { model.toggleCheck(on: block.id) },
                        onReturn: { before, after in
                            model.splitBlock(block.id, before: before, after: after)
                        },
                        onBackspaceAtStart: { model.backspaceAtStart(of: block.id) },
                        onIndent: { model.indent(block.id, by: $0) },
                        onFocus: { model.focusedBlockID = block.id },
                        onTransform: { kind, text in model.transform(block.id, to: kind, text: text) },
                        onSlashQuery: { model.slashQuery = $0 },
                        onLinkQuery: { model.linkQuery = $0 },
                        onSketchDrawing: { model.setSketchDrawing($0, on: block.id) },
                        onSketchHeight: { model.setSketchHeight($0, on: block.id) }
                    )
                    .id(block.id)
                }

                // Tapping under the last block puts the caret in it, the way
                // every document editor behaves. Without this the bottom half of
                // a short page is dead space.
                Color.clear
                    .frame(height: 160)
                    .contentShape(.rect)
                    .onTapGesture { model.focusedBlockID = model.blocks.last?.id }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }

            InkCanvasView(
                data: Binding(get: { model.drawingData }, set: { model.setDrawing($0) }),
                isInkMode: model.isInking,
                allowsFingerDrawing: !layout.isRegular || drawWithFinger,
                onPencilShortcut: {
                    model.isInking.toggle()
                    if model.isInking { model.focusedBlockID = nil }
                },
                height: max(contentHeight, 320),
                isDark: scheme == .dark
            )
            .frame(height: max(contentHeight, 320))
            .allowsHitTesting(true)
        }
    }

    // MARK: - Backlinks

    /// The same list in a column of its own, for a pane wide enough to spare
    /// the width.
    private var backlinksInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Linked from")
                    .font(LifeOSType.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(secondary)

                ForEach(model.backlinks) { link in
                    backlinkRow(link)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(LifeOSTokens.canvas.resolve(scheme))
    }

    private var backlinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 8)

            Label("\(model.backlinks.count) \(model.backlinks.count == 1 ? "page links" : "pages link") here",
                  systemImage: "arrow.turn.up.left")
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(secondary)

            ForEach(model.backlinks) { link in
                backlinkRow(link)
            }
        }
        .padding(.top, 20)
    }

    private func backlinkRow(_ link: NoteBacklink) -> some View {
        Button {
            onOpenLinked(link.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(NoteAccentPalette.dot(link.accent, scheme))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                        .font(LifeOSType.secondary.weight(.medium))
                        .foregroundStyle(primary)
                    Text(link.context)
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LifeOSTokens.tileSurface.resolve(scheme))
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.isInking.toggle()
                if model.isInking { model.focusedBlockID = nil }
            } label: {
                Image(systemName: model.isInking ? "scribble.variable" : "pencil.tip.crop.circle")
                    .foregroundStyle(model.isInking ? LifeOSTokens.accent : primary)
            }
            .accessibilityLabel(model.isInking ? "Stop drawing" : "Draw on this page")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Change page icon", systemImage: "face.smiling") { showEmojiPicker = true }
                Menu("Page color", systemImage: "paintpalette") {
                    ForEach(NoteAccent.allCases) { accent in
                        Button(accent.title) { model.setAccent(accent) }
                    }
                }
                Divider()
                Button(model.isFavorite ? "Remove from favourites" : "Add to favourites",
                       systemImage: model.isFavorite ? "star.slash" : "star") {
                    model.toggleFavorite()
                }
                Button(model.isArchived ? "Restore from archive" : "Archive",
                       systemImage: model.isArchived ? "tray.and.arrow.up" : "archivebox") {
                    model.toggleArchive()
                }
                Divider()
                ShareLink(item: NoteBlockParser.markdown(model.blocks)) {
                    Label("Share as Markdown", systemImage: "square.and.arrow.up")
                }
                if model.drawingData != nil {
                    Button("Clear drawing", systemImage: "eraser", role: .destructive) {
                        confirmClearDrawing = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(primary)
            }
            .accessibilityLabel("Page options")
        }
    }
}

/// A short emoji grid for the page icon.
///
/// Not the system emoji keyboard: reaching it needs a text field, and a text
/// field that exists only to be typed one emoji into then has to be prevented
/// from accepting anything else.
struct NoteIconPicker: View {
    let selected: String
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let icons = [
        "\u{1F4C4}", "\u{1F4DD}", "\u{1F4D3}", "\u{1F4DA}", "\u{1F5C2}", "\u{1F3AF}",
        "\u{1F680}", "\u{1F4A1}", "\u{1F331}", "\u{1F3C3}", "\u{1F4B0}", "\u{1F9E0}",
        "\u{2764}", "\u{2B50}", "\u{1F525}", "\u{1F5D3}", "\u{1F4CC}", "\u{1F517}",
        "\u{1F52C}", "\u{1F3A8}", "\u{1F3B5}", "\u{1F374}", "\u{2708}", "\u{1F3E0}",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            onPick(icon)
                            dismiss()
                        } label: {
                            Text(icon)
                                .font(LifeOSType.screenTitle.weight(.regular))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(icon == selected ? Color.primary.opacity(0.08) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Page icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("None") {
                        onPick("")
                        dismiss()
                    }
                }
            }
        }
    }
}
