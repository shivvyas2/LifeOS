import Foundation

/// The running session, saved so it outlives the app being closed or
/// killed while the phone is locked.
public struct ActiveFocusSession: Codable, Equatable, Sendable {
    public var setup: FocusSetup
    /// The source actually playing, after any Apple Music fallback.
    public var source: SoundSource
    public var timer: FocusTimer
    public var startedAt: Date
    public var taskID: UUID?
    public var taskTitle: String?

    public init(setup: FocusSetup, source: SoundSource, timer: FocusTimer, startedAt: Date, taskID: UUID?, taskTitle: String?) {
        self.setup = setup; self.source = source; self.timer = timer
        self.startedAt = startedAt; self.taskID = taskID; self.taskTitle = taskTitle
    }

    static let key = "focus.activeSession"

    public static func load(from defaults: UserDefaults) -> ActiveFocusSession? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ActiveFocusSession.self, from: $0) }
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    public static func clear(from defaults: UserDefaults) { defaults.removeObject(forKey: key) }
}
