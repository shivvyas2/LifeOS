import Foundation
import Persistence

/// Collects the events a turn actually touched, so the screen can draw them
/// rather than re-reading them out of the model's prose.
///
/// The tools hand the model text, because that is what a model consumes. The
/// same events arrive here as values, because that is what a card needs. The
/// alternative was parsing the reply back into events, which means trusting a
/// model to have restated a date correctly in order to render it correctly,
/// and a card that disagrees with the sentence above it is worse than no card.
public actor CalendarEventCollector {
    private var events: [CalendarEventSnapshot] = []
    private var seen: Set<UUID> = []

    public init() {}

    /// Deduplicated: a turn that asks about today and then about this week
    /// surfaces the same lunch twice, and the person should see one lunch.
    public func record(_ incoming: [CalendarEventSnapshot]) {
        for event in incoming where seen.insert(event.id).inserted {
            events.append(event)
        }
    }

    /// Chronological, whatever order the tools ran in. A model that asks about
    /// Friday before Wednesday should not produce a card list in that order.
    public func collected() -> [CalendarEventSnapshot] {
        events.sorted { $0.startDate < $1.startDate }
    }
}
