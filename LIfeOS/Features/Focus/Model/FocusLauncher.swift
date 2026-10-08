import Foundation
import Soundscape

/// Any screen (Today, a project task, Siri) asks for the setup sheet here;
/// the root view presents it.
@MainActor @Observable
final class FocusLauncher {
    static let shared = FocusLauncher()

    struct Request: Identifiable, Equatable {
        let id = UUID()
        var mood: Mood?
        var taskID: UUID?
        var taskTitle: String?
    }

    var request: Request?

    func open(mood: Mood? = nil, taskID: UUID? = nil, taskTitle: String? = nil) {
        request = Request(mood: mood, taskID: taskID, taskTitle: taskTitle)
    }
}
