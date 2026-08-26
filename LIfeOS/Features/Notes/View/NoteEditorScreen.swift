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
    var onOpenLinked: (UUID) -> Void
    var onClose: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    /// Measured, so the ink canvas covers exactly the blocks. A canvas sized to
    /// the screen instead would clip strokes the moment the page scrolled.
    @State private var contentHeight: CGFloat = 0
    @State private var showEmojiPicker = false

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                pageBody
                if !model.backlinks.isEmpty { backlinks }
                Spacer(minLength: 120)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: layout.isRegular ? .center : .leading)
            .padding(.horizontal, layout.gutter)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.focusedBlockID != nil {
                NoteAccessoryBar(
                    slashQuery: model.slashQuery,
                    linkSuggestions: model.linkSuggestions,
                    linkQuery: model.linkQuery,
                    currentKind: focusedKind,
                    onPickBlock: { model.applySlashCommand($0) },
                    onPickLink: { model.completeLink(with: $0) },
                    onIndent: { delta in
                        if let id = model.focusedBlockID { model.indent(id, by: delta) }
                    },
                    onToggleInk: { model.isInking.toggle() },
                    isInking: model.isInking,
                    onDismissKeyboard: { model.focusedBlockID = nil }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .toolbar { toolbar }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.flush() }
        .animation(.easeInOut(duration: 0.15), value: model.slashQuery)
        .animation(.easeInOut(duration: 0.15), value: model.linkQuery)
    }

    private var focusedKind: NoteBlockKind {
        guard let id = model.focusedBlockID, let index = model.index(of: id) else { return .paragraph }
        return model.blocks[index].kind
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showEmojiPicker = true
                } label: {
                    Text(model.icon.isEmpty ? "\u{1F4C4}" : model.icon)
                        .font(.system(size: 32))
                        .opacity(model.icon.isEmpty ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page icon")

                Spacer(minLength: 0)
            }

            TextField("Untitled", text: $model.title, axis: .vertical)
                .font(.noteSerif(layout.isRegular ? 36 : 30))
                .foregroundStyle(primary)
                .textFieldStyle(.plain)
                .lineLimit(1...3)

            metaRow
        }
        .padding(.bottom, 18)
        .sheet(isPresented: $showEmojiPicker) {
            NoteIconPicker(selected: model.icon) { model.setIcon($0) }
                .presentationDetents([.height(320)])
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            if let entryDate = model.entryDate {
                chip(entryDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                     systemImage: "calendar")
            }

            Menu {
                ForEach(PlanStatus.allCases, id: \.self) { status in
                    Button(status.title) { model.setStatus(status) }
                }
            } label: {
                chip(model.status.title, systemImage: "circle.dotted")
            }

            Menu {
                ForEach(NoteAccent.allCases) { accent in
                    Button(accent.title) { model.setAccent(accent) }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(NoteAccentPalette.dot(model.accent, scheme))
                        .frame(width: 9, height: 9)
                    Text(model.accent.title)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().strokeBorder(secondary.opacity(0.28), lineWidth: 1))
            }

            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().strokeBorder(secondary.opacity(0.28), lineWidth: 1))
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
                        onLinkQuery: { model.linkQuery = $0 }
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
                height: max(contentHeight, 320),
                isDark: scheme == .dark
            )
            .frame(height: max(contentHeight, 320))
            .allowsHitTesting(true)
        }
    }

    // MARK: - Backlinks

    private var backlinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 8)

            Label("\(model.backlinks.count) \(model.backlinks.count == 1 ? "page links" : "pages link") here",
                  systemImage: "arrow.turn.up.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondary)

            ForEach(model.backlinks) { link in
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
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(primary)
                            Text(link.context)
                                .font(.system(size: 13))
                                .foregroundStyle(secondary)
                                .lineLimit(2)
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
            }
        }
        .padding(.top, 20)
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
                        model.setDrawing(nil)
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
                                .font(.system(size: 28))
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
