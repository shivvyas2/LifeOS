#if DEBUG
import SwiftUI
import Persistence
import SwiftData
import Soundscape

/// `--page=focus`: a button that opens the real setup sheet, then the real
/// session screen on an in-memory store. `--page=focus-task` adds a task.
struct FocusDesignPreview: View {
    let page: String
    @State private var model = FocusSessionModel(defaults: UserDefaults(suiteName: "focus-preview")!, notifies: false)
    @State private var showSetup = false
    @State private var container = try! LifeOSContainer.make(inMemory: true)

    private var taskTitle: String? { page == "focus-task" ? "Write the launch post" : nil }

    var body: some View {
        Button("Open focus") { showSetup = true }
            .accessibilityIdentifier("focus.open")
            .sheet(isPresented: $showSetup) {
                FocusSetupSheet(initial: model.preferences.setup(for: model.preferences.lastMood),
                                preferences: model.preferences, taskTitle: taskTitle) { setup in
                    Task {
                        await model.start(setup, inputs: FocusInputs(), context: container.mainContext,
                                          taskID: taskTitle == nil ? nil : UUID(), taskTitle: taskTitle)
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { model.isPresented }, set: { _ in })) {
                FocusSessionScreen(model: model)
            }
    }
}
#endif
