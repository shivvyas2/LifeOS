import SwiftUI
import DesignSystem
import AppSurfaces

/// Every activity, grouped, with a search field. A dialog on every device.
struct ActivityPickerSheet: View {
    @Binding var selection: ActivityType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""

    private var sections: [(group: ActivityType.Group, types: [ActivityType])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ActivityCatalog.grouped() }
        let hits = Set(ActivityCatalog.search(trimmed).map(\.name))
        return ActivityCatalog.grouped()
            .map { (group: $0.group, types: $0.types.filter { hits.contains($0.name) }) }
            .filter { !$0.types.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(sections, id: \.group) { section in
                    Section {
                        ForEach(section.types) { type in
                            Button {
                                selection = type
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: type.symbol).frame(width: 28)
                                    Text(type.name)
                                    Spacer()
                                    if type == selection { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
                                }
                                .frame(minHeight: 44)
                            }
                            .tint(.primary)
                            .listRowBackground(Color.clear)
                            .accessibilityAddTraits(type == selection ? .isSelected : [])
                        }
                    } header: {
                        Text(section.group.rawValue).editorialEyebrow()
                    }
                }
            }
            // A plain list on the app's paper with tracked group headings,
            // rather than the system's grey grouped inset list.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
            .navigationTitle("All activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(LifeOSTokens.primaryText.resolve(scheme))
    }
}
