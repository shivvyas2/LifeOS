import SwiftUI
import DesignSystem
import Persistence

/// One feature: its note, milestone, branch, and tasks, in the editorial
/// style. `commits` is where the branch's commits and its PR go.
struct FeatureDetailView<Commits: View>: View {
    @Bindable var model: ProjectsViewModel
    let featureID: UUID
    /// Branches named for this feature when more than one is.
    var candidates: [String] = []
    /// Every branch in the repo, for picking one by hand.
    var branches: [String] = []
    @ViewBuilder var commits: () -> Commits

    @Environment(\.colorScheme) private var scheme
    @State private var note = ""
    @State private var branch = ""
    @State private var newTask = ""
    @State private var revision = 0

    private var feature: FeatureSnapshot? { _ = revision; _ = model.projects; return try? model.store?.feature(id: featureID) }
    private var tasks: [ProjectTaskSnapshot] {
        _ = revision; _ = model.projects
        guard let feature else { return [] }
        return ((try? model.store?.tasks(projectID: feature.projectID)) ?? []).filter { $0.featureID == featureID }
    }
    private var milestones: [MilestoneSnapshot] {
        guard let feature else { return [] }
        return (try? model.store?.milestones(projectID: feature.projectID)) ?? []
    }

    var body: some View {
        if let feature {
            VStack(alignment: .leading, spacing: Space.x3) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("Feature").editorialEyebrow()
                    HStack(alignment: .firstTextBaseline) {
                        Text(feature.title).font(Editorial.headline(30))
                        Spacer()
                        StageTag(stage: feature.stage)
                    }
                    if !feature.stageDetail.isEmpty {
                        Text(feature.stageDetail).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    Hairline().padding(.top, Space.x1)
                }

                VStack(alignment: .leading, spacing: Space.x2) {
                    TextField("Note", text: $note, axis: .vertical)
                        .font(LifeOSType.body)
                        .onSubmit { model.updateFeature(featureID, note: note) }
                    Hairline()
                    EditorialRow("Milestone") {
                        Picker("Milestone", selection: Binding(
                            get: { feature.milestoneID },
                            set: { model.updateFeature(featureID, milestoneID: .some($0)); revision += 1 })) {
                            Text("None").tag(UUID?.none)
                            ForEach(milestones) { Text($0.title).tag(UUID?.some($0.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .editorialCard()

                VStack(alignment: .leading, spacing: Space.x2) {
                    EditorialSectionHeader(index: 1, title: "Branch")
                    if let linked = feature.branch {
                        HStack {
                            Text(linked).font(LifeOSType.body.monospaced())
                            Spacer()
                            Button("Copy") { UIPasteboard.general.string = linked }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                            Button("Unlink") { model.updateFeature(featureID, branch: .some(nil)); revision += 1 }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                        }
                    } else {
                        TextField("Branch name", text: $branch)
                            .font(LifeOSType.body.monospaced())
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit(linkTypedBranch)
                        HStack(spacing: Space.x1) {
                            Button("Link", action: linkTypedBranch).buttonStyle(.editorial(.primary, size: .compact))
                            Button("Copy") { UIPasteboard.general.string = branch }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                            if !branches.isEmpty {
                                Menu("Pick a branch") {
                                    ForEach(candidates + branches.filter { !candidates.contains($0) }, id: \.self) { name in
                                        Button(name) { model.updateFeature(featureID, branch: .some(name)); revision += 1 }
                                    }
                                }
                                .font(LifeOSType.label)
                            }
                        }
                        if candidates.count > 1 {
                            Text("Several branches are named for this feature. Pick the one it is built on.")
                                .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                        }
                    }
                }

                commits()

                VStack(alignment: .leading, spacing: Space.x1) {
                    EditorialSectionHeader(index: 3, title: "Tasks") {
                        Text("\(feature.doneTasks)/\(feature.doneTasks + feature.openTasks)")
                            .font(LifeOSType.label.monospacedDigit()).foregroundStyle(Editorial.quietInk(scheme))
                    }
                    ForEach(tasks) { task in
                        HStack(spacing: Space.x1) {
                            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Editorial.quietInk(scheme))
                            Text(task.title).font(LifeOSType.body)
                                .strikethrough(task.status == .done)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        TextField("New task", text: $newTask).onSubmit(addTask)
                        Button("Add", action: addTask).buttonStyle(.editorial(.secondary, size: .compact))
                    }
                }
            }
            .onAppear {
                note = feature.note
                branch = ""
            }
        }
    }

    private func linkTypedBranch() {
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.updateFeature(featureID, branch: .some(name))
        revision += 1
    }

    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let feature, let id = model.createTask(in: feature.projectID, title: title) else { return }
        model.updateTask(id, featureID: .some(featureID))
        newTask = ""
        revision += 1
    }
}
