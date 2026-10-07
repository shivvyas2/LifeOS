import SwiftUI
import DesignSystem
import Persistence

/// A task's title, notes, status, owner, milestone, due date and time block.
struct TaskSheet: View {
    enum Target: Identifiable, Hashable {
        case task(UUID)
        case new(start: Date?)
        var id: String {
            switch self {
            case .task(let id): id.uuidString
            case .new(let start): "new-\(start?.timeIntervalSince1970 ?? 0)"
            }
        }
    }

    @Bindable var model: ProjectsViewModel
    let projectID: UUID
    let target: Target
    let members: [ProjectMemberSnapshot]
    let milestones: [MilestoneSnapshot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var title = ""
    @State private var notes = ""
    @State private var status: ProjectStatus = .todo
    @State private var owner: UUID?
    @State private var milestone: UUID?
    @State private var hasDue = false
    @State private var due = Date.now
    @State private var hasBlock = false
    @State private var start = Date.now
    @State private var end = Date.now.addingTimeInterval(3_600)
    @State private var loaded = false

    private var existing: ProjectTaskSnapshot? {
        guard case .task(let id) = target else { return nil }
        return ((try? model.store?.tasks(projectID: projectID)) ?? []).first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title).font(LifeOSType.rowTitle)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Owner", selection: $owner) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(members) { Text(model.name($0.userID)).tag(UUID?.some($0.userID)) }
                    }
                    Picker("Milestone", selection: $milestone) {
                        Text("None").tag(UUID?.none)
                        ForEach(milestones) { Text($0.title).tag(UUID?.some($0.id)) }
                    }
                }
                Section {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                    Toggle("Time block", isOn: $hasBlock)
                    if hasBlock {
                        DatePicker("Starts", selection: $start)
                        DatePicker("Ends", selection: $end, in: start.addingTimeInterval(60)...)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete task", role: .destructive) {
                            if case .task(let id) = target { model.deleteTask(id) }
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .navigationTitle(existing == nil ? "New task" : "Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: fill)
            // Moving the start keeps the block's length; the end never falls
            // on or before the start.
            .onChange(of: start) { old, new in
                let length = max(end.timeIntervalSince(old), 15 * 60)
                end = new.addingTimeInterval(length)
            }
        }
    }

    private func fill() {
        guard !loaded else { return }
        loaded = true
        if let task = existing {
            title = task.title; notes = task.notes; status = task.status; owner = task.ownerID
            milestone = task.milestoneID
            if let d = task.dueOn { hasDue = true; due = d }
            if let s = task.startsAt { hasBlock = true; start = s; end = task.endsAt ?? s.addingTimeInterval(3_600) }
        } else if case .new(let slot) = target {
            owner = model.me
            if let slot { hasBlock = true; start = slot; end = slot.addingTimeInterval(3_600) }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let id: UUID?
        switch target {
        case .task(let existingID): id = existingID
        case .new: id = model.createTask(in: projectID, title: trimmed)
        }
        guard let id else { return }
        model.updateTask(id, title: trimmed, notes: notes, ownerID: .some(owner), milestoneID: .some(milestone),
                         dueOn: .some(hasDue ? due : nil), startsAt: .some(hasBlock ? start : nil),
                         endsAt: .some(hasBlock ? end : nil))
        if existing?.status != status { model.moveTask(id, to: status, at: .max) }
    }
}
