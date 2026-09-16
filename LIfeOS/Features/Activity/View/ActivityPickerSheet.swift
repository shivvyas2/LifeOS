import SwiftUI
import DesignSystem
import AppSurfaces

/// Every activity, grouped, with a search field. A dialog on every device.
struct ActivityPickerSheet: View {
    @Binding var selection: ActivityType
    var onChoose: (ActivityType) -> Void
    @Environment(\.dismiss) private var dismiss
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
                    Section(section.group.rawValue) {
                        ForEach(section.types) { type in
                            Button {
                                selection = type
                                onChoose(type)
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
                            .accessibilityAddTraits(type == selection ? .isSelected : [])
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
            .navigationTitle("All activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(LifeOSTokens.accent)
    }
}
