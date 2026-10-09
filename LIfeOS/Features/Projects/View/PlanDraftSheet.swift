import SwiftUI
import DesignSystem
import Insights

/// LIFO's draft of a project's features, edited before anything is saved.
struct PlanDraftSheet: View {
    @Bindable var model: ProjectsViewModel
    let projectID: UUID
    let github: ProjectGitHubModel?
    /// Previews start from a fixed draft instead of asking LIFO.
    var preset: [PlanDraft.Item]? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var items: [PlanDraft.Item] = []
    @State private var drafting = false
    @State private var message: String?
    @State private var nudge = ""

    var body: some View {
        NavigationStack {
            List {
                if drafting {
                    HStack { ProgressView(); Text("LIFO is drafting the plan…") }
                }
                if let message { Text(message).font(LifeOSType.secondary) }
                ForEach(Array($items.enumerated()), id: \.element.id) { index, $item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Feature \(index + 1)", text: $item.title)
                                .font(LifeOSType.rowTitle.weight(.semibold))
                                .accessibilityLabel("Feature \(index + 1)")
                            Button { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(item.title)")
                        }
                        TextField("Note", text: $item.note, axis: .vertical).font(LifeOSType.secondary)
                        Text(item.branch).font(LifeOSType.caption.monospaced()).foregroundStyle(Editorial.quietInk(scheme))
                    }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                Section {
                    TextField("Nudge, e.g. smaller, or start with auth", text: $nudge)
                    Button("Redraft") { Task { await draft() } }.disabled(drafting)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Draft plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") { model.keepDraft(items, in: projectID); dismiss() }
                        .disabled(items.isEmpty || drafting)
                }
            }
            .task {
                if let preset { items = preset } else { await draft() }
            }
        }
    }

    private func draft() async {
        drafting = true
        message = nil
        defer { drafting = false }
        switch await model.draftPlan(projectID: projectID, nudge: nudge.isEmpty ? nil : nudge, github: github) {
        case .success(let drafted): items = drafted
        case .failure(.exhausted): message = "That is today's draft used. Add features by hand, or draft again tomorrow."
        case .failure(.refused(let reason)): message = reason
        case .failure(.notSignedIn): message = "Sign in to draft with LIFO."
        case .failure(.unavailable): message = "LIFO could not be reached. Try again, or add features by hand."
        }
    }
}
