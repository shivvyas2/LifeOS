import SwiftUI
import DesignSystem
import Soundscape

/// Mood, sound, timer and texture. Everything starts at what was used last.
struct FocusSetupSheet: View {
    @State private var setup: FocusSetup
    private let preferences: FocusPreferences
    private let taskTitle: String?
    private let onStart: (FocusSetup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(initial: FocusSetup, preferences: FocusPreferences, taskTitle: String?, onStart: @escaping (FocusSetup) -> Void) {
        _setup = State(initialValue: initial)
        self.preferences = preferences
        self.taskTitle = taskTitle
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if let taskTitle {
                        Text(taskTitle).font(LifeOSType.rowTitle).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    moods
                    choice("Sound", SoundSource.allCases, \.self, \.title, selection: $setup.source, id: "source")
                    choice("Timer", setup.mood.presets, \.id, \.title, selection: $setup.presetID, id: "preset")
                    if setup.mood == .focus || setup.mood == .brainstorm {
                        Toggle("Stop after 4 blocks", isOn: Binding(get: { setup.blocks != nil }, set: { setup.blocks = $0 ? 4 : nil }))
                            .font(LifeOSType.body)
                    }
                    if setup.source == .soundscape {
                        choice("Texture", Texture.allCases, \.self, \.title, selection: $setup.texture, id: "texture")
                    }
                }
                .padding(Space.x2)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Start") { onStart(setup); dismiss() }
                    .buttonStyle(.editorial(.primary, size: .regular, fullWidth: true))
                    .accessibilityIdentifier("focus.start")
                    .padding(Space.x2)
            }
            .navigationTitle("Focus session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var moods: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.x1) {
            ForEach(Mood.allCases, id: \.self) { mood in
                Button {
                    let remembered = preferences.setup(for: mood)
                    setup = FocusSetup(mood: mood, source: setup.source, presetID: remembered.presetID,
                                       blocks: remembered.blocks, texture: remembered.texture)
                } label: {
                    Text(mood.title).font(LifeOSType.rowTitle)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(setup.mood == mood ? LifeOSTokens.accent.opacity(0.18) : .clear)
                        .overlay(RoundedRectangle(cornerRadius: Radius.small).stroke(Editorial.rule(scheme)))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus.mood.\(mood.rawValue)")
                .accessibilityAddTraits(setup.mood == mood ? .isSelected : [])
            }
        }
    }

    private func choice<Item, Value: Hashable>(_ title: String, _ items: [Item], _ value: KeyPath<Item, Value>,
                                               _ label: KeyPath<Item, String>, selection: Binding<Value>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title.uppercased()).editorialEyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x1) {
                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
                        Button(item[keyPath: label]) { selection.wrappedValue = item[keyPath: value] }
                            .buttonStyle(.editorial(selection.wrappedValue == item[keyPath: value] ? .primary : .secondary,
                                                    size: .compact, fullWidth: false))
                            .accessibilityIdentifier("focus.\(id).\(item[keyPath: value])")
                    }
                }
            }
        }
    }
}
