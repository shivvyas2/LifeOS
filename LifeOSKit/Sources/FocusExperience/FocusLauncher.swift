#if os(iOS)
import Foundation
import Soundscape

/// Any screen (Today, a project task, Siri) asks for the setup sheet here;
/// the root view presents it.
@MainActor @Observable
public final class FocusLauncher {
    public static let shared = FocusLauncher()

    public struct Request: Identifiable, Equatable {
        public let id = UUID()
        public var mood: Mood?
        public var taskID: UUID?
        public var taskTitle: String?

        public init(mood: Mood? = nil, taskID: UUID? = nil, taskTitle: String? = nil) {
            self.mood = mood; self.taskID = taskID; self.taskTitle = taskTitle
        }
    }

    public var request: Request?

    public func open(mood: Mood? = nil, taskID: UUID? = nil, taskTitle: String? = nil) {
        request = Request(mood: mood, taskID: taskID, taskTitle: taskTitle)
    }
}
#endif
