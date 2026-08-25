import Foundation

public protocol BriefStore: Sendable {
    func load(for date: Date) -> DailyBrief?
    func save(_ brief: DailyBrief, for date: Date)
}

/// Backing for tests and previews. The app substitutes a SwiftData store when
/// the coach screen is built.
public final class InMemoryBriefStore: BriefStore, @unchecked Sendable {
    private let lock = NSLock()
    private var briefs: [Date: DailyBrief] = [:]

    public init() {}

    public func load(for date: Date) -> DailyBrief? {
        lock.withLock { briefs[date] }
    }

    public func save(_ brief: DailyBrief, for date: Date) {
        lock.withLock { briefs[date] = brief }
    }
}

/// One brief per calendar day.
///
/// Without this the brief regenerates every time Today appears, so its cost
/// tracks how often the app is opened rather than how many days have passed.
/// That is free on-device and the single largest line item the moment the
/// tier moves, which is why it is built now rather than when it starts to
/// hurt.
///
/// An actor, and with an in-flight map, because the store lookup and the
/// generation are two steps: two callers arriving for the same day before
/// either has finished would both miss the store and both generate. Free
/// today, two billed model runs tomorrow — the exact cost this type exists to
/// prevent. Concurrent callers for the same day await one generation instead.
public actor BriefCache {

    private let store: any BriefStore
    private let calendar: Calendar
    private var inFlight: [Date: Task<CoachResult<DailyBrief>, Never>] = [:]

    public init(store: any BriefStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func brief(
        for date: Date,
        generate: @Sendable @escaping () async -> CoachResult<DailyBrief>
    ) async -> CoachResult<DailyBrief> {
        let day = calendar.startOfDay(for: date)

        if let cached = store.load(for: day) {
            return .answered(cached)
        }
        if let existing = inFlight[day] {
            return await existing.value
        }

        let task = Task { await generate() }
        inFlight[day] = task
        let result = await task.value
        inFlight[day] = nil

        // Only a real answer is kept. Caching a refusal or an outage would
        // strand the user without a brief until midnight.
        if case .answered(let brief) = result {
            store.save(brief, for: day)
        }
        return result
    }
}
