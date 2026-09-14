import SwiftUI
import DesignSystem

/// Three questions, asked once on the library's first open and editable from
/// its toolbar. Nothing is guessed: until a goal is chosen the planner says so
/// rather than inventing one.
struct TrainingPreferencesSheet: View {
    @Bindable var model: WorkoutLibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var goal: String
    @State private var equipment: Set<String>
    @State private var minutes: Int

    init(model: WorkoutLibraryViewModel) {
        self.model = model
        _goal = State(initialValue: model.preferredGoal ?? WorkoutLibraryViewModel.goalOptions[0])
        _equipment = State(initialValue: Set(model.preferredEquipment))
        _minutes = State(initialValue: model.preferredMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you training for?") {
                    Picker("Goal", selection: $goal) {
                        ForEach(WorkoutLibraryViewModel.goalOptions, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    ForEach(WorkoutLibraryViewModel.equipmentOptions, id: \.self) { item in
                        Button {
                            if equipment.contains(item) { equipment.remove(item) } else { equipment.insert(item) }
                        } label: {
                            HStack {
                                Text(item.capitalized)
                                Spacer()
                                if equipment.contains(item) {
                                    Image(systemName: "checkmark").font(.caption.bold())
                                        .foregroundStyle(LifeOSTokens.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(equipment.contains(item) ? .isSelected : [])
                    }
                } header: {
                    Text("What can you train with?")
                } footer: {
                    Text("Pick everything you have. The library filters to it.")
                }
                Section("How long is a session?") {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(WorkoutLibraryViewModel.minuteOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Training preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.savePreferences(goal: goal, equipment: equipment.sorted(), minutes: minutes)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(LifeOSTokens.accent)
    }
}
