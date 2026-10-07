import Foundation

/// A piece of Today the person can place, hide or bring back.
public enum TodayModule: String, CaseIterable, Codable, Sendable {
    case nextUp, month, tasks, github, scheduledWorkout, steps, sleep, weight, recovery, weather, spentToday, fromLifo, projects

    public var title: String {
        switch self {
        case .nextUp: "Next up"
        case .month: "Month"
        case .tasks: "Today's tasks"
        case .github: "GitHub"
        case .scheduledWorkout: "Scheduled workout"
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .weight: "Weight"
        case .recovery: "Recovery"
        case .weather: "Weather"
        case .spentToday: "Spent today"
        case .fromLifo: "From LIFO"
        case .projects: "Projects"
        }
    }

    public var isTile: Bool { [.steps, .sleep, .weight, .recovery].contains(self) }

    /// What the day's model must load for this module; nil when Today reads
    /// it from its own snapshot.
    public var daySection: DaySection? {
        switch self {
        case .tasks: .checklist
        case .weather: .weather
        case .spentToday: .money
        case .fromLifo: .nudges
        case .github: .project
        default: nil
        }
    }
}

public enum TodayColumn: Sendable { case left, right }

/// One line of Today: a module, or two tiles side by side.
public enum TodayRow: Equatable, Identifiable, Sendable {
    case single(TodayModule)
    case pair(TodayModule, TodayModule?)

    public var modules: [TodayModule] {
        switch self {
        case .single(let module): [module]
        case .pair(let first, let second): [first] + (second.map { [$0] } ?? [])
        }
    }

    public var id: String {
        switch self {
        case .single(let module): module.rawValue
        case .pair(let first, let second): "\(first.rawValue)+\(second?.rawValue ?? "")"
        }
    }
}

/// Today's arrangement: two columns, each in order. The phone reads the left
/// then the right as one list. Anything in neither is hidden, in the tray.
public struct TodayLayout: Equatable, Sendable {
    public private(set) var left: [TodayModule]
    public private(set) var right: [TodayModule]

    public init(left: [TodayModule], right: [TodayModule]) {
        var seen = Set<TodayModule>()
        self.left = left.filter { seen.insert($0).inserted }
        self.right = right.filter { seen.insert($0).inserted }
    }

    /// The approved iPad estate arrangement; GitHub, Weather, Spent today and
    /// From LIFO wait in the tray.
    public static let standard = TodayLayout(left: [.nextUp, .month, .tasks, .scheduledWorkout],
                                             right: [.steps, .sleep, .weight, .recovery])

    public var hidden: [TodayModule] { TodayModule.allCases.filter { column(of: $0) == nil } }
    public var phoneOrder: [TodayModule] { left + right }

    public func column(of module: TodayModule) -> TodayColumn? {
        if left.contains(module) { return .left }
        if right.contains(module) { return .right }
        return nil
    }

    public mutating func move(_ module: TodayModule, to column: TodayColumn, at index: Int) {
        left.removeAll { $0 == module }
        right.removeAll { $0 == module }
        switch column {
        case .left: left.insert(module, at: min(max(index, 0), left.count))
        case .right: right.insert(module, at: min(max(index, 0), right.count))
        }
    }

    /// A drop: `module` lands just before or just after `target`, in
    /// `target`'s column. Dropped on itself, nothing moves.
    public mutating func place(_ module: TodayModule, nextTo target: TodayModule, after: Bool) {
        guard module != target, column(of: target) != nil else { return }
        hide(module)
        guard let side = column(of: target) else { return }
        let list = side == .left ? left : right
        let index = (list.firstIndex(of: target) ?? 0) + (after ? 1 : 0)
        move(module, to: side, at: index)
    }

    public mutating func hide(_ module: TodayModule) {
        left.removeAll { $0 == module }
        right.removeAll { $0 == module }
    }

    /// A shown module stays where it is.
    public mutating func add(_ module: TodayModule, to column: TodayColumn) {
        guard self.column(of: module) == nil else { return }
        move(module, to: column, at: .max)
    }

    /// To the shorter column, a tile counting as half a module.
    public mutating func add(_ module: TodayModule) {
        func weight(_ modules: [TodayModule]) -> Double { modules.reduce(0) { $0 + ($1.isTile ? 0.5 : 1) } }
        add(module, to: weight(right) < weight(left) ? .right : .left)
    }

    /// One step through the phone order, crossing between the columns.
    public mutating func moveUp(_ module: TodayModule) {
        if let index = left.firstIndex(of: module) {
            if index > 0 { left.swapAt(index, index - 1) }
        } else if let index = right.firstIndex(of: module) {
            if index > 0 { right.swapAt(index, index - 1) } else { move(module, to: .left, at: .max) }
        }
    }

    public mutating func moveDown(_ module: TodayModule) {
        if let index = right.firstIndex(of: module) {
            if index < right.count - 1 { right.swapAt(index, index + 1) }
        } else if let index = left.firstIndex(of: module) {
            if index < left.count - 1 { left.swapAt(index, index + 1) } else { move(module, to: .right, at: 0) }
        }
    }

    public mutating func moveToOtherColumn(_ module: TodayModule) {
        switch column(of: module) {
        case .left: move(module, to: .right, at: 0)
        case .right: move(module, to: .left, at: 0)
        case nil: break
        }
    }

    /// The first time GitHub connects, its card joins the left column.
    public mutating func offerGitHub() { add(.github, to: .left) }

    /// Consecutive tiles share a row, two at a time.
    public static func rows(_ modules: [TodayModule]) -> [TodayRow] {
        var rows: [TodayRow] = []
        var pending: TodayModule?
        for module in modules {
            if module.isTile {
                if let first = pending { rows.append(.pair(first, module)); pending = nil } else { pending = module }
            } else {
                if let first = pending { rows.append(.pair(first, nil)); pending = nil }
                rows.append(.single(module))
            }
        }
        if let first = pending { rows.append(.pair(first, nil)) }
        return rows
    }

    /// What the day's model loads for the modules on screen.
    public static func sections(for visible: [TodayModule]) -> Set<DaySection> {
        Set(visible.compactMap(\.daySection))
    }

    private struct Stored: Codable { var left: [String]; var right: [String] }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(Stored(left: left.map(\.rawValue), right: right.map(\.rawValue)))) ?? Data()
    }

    /// Names this build does not know are dropped; modules the saved layout
    /// never had stay hidden; nothing saved is the default.
    public static func decoded(_ data: Data?) -> TodayLayout {
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .standard }
        return TodayLayout(left: stored.left.compactMap(TodayModule.init(rawValue:)),
                           right: stored.right.compactMap(TodayModule.init(rawValue:)))
    }
}
