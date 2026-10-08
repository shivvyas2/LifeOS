import AppIntents
import Soundscape

enum FocusMoodOption: String, AppEnum {
    case focus, brainstorm, relax, sleep
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [FocusMoodOption: DisplayRepresentation] = [
        .focus: "Focus", .brainstorm: "Brainstorm", .relax: "Relax", .sleep: "Sleep",
    ]
}

struct StartFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a focus session"
    static let description = IntentDescription("Opens Almanac's focus session setup, ready to start.")
    static let openAppWhenRun = true

    @Parameter(title: "Mood") var mood: FocusMoodOption?

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusLauncher.shared.open(mood: mood.flatMap { Mood(rawValue: $0.rawValue) })
        return .result()
    }
}

struct AlmanacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusSessionIntent(),
                    phrases: ["Start a focus session in \(.applicationName)", "Focus with \(.applicationName)"],
                    shortTitle: "Focus", systemImageName: "timer")
    }
}
