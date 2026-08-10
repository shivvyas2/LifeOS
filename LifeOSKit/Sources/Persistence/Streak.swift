import Foundation

/// `statuses` must be ordered most-recent-first.
/// Days with no data are transparent: they neither extend nor break a streak.
public func currentStreak(statuses: [DayStatus]) -> Int {
    var count = 0
    for status in statuses {
        switch status {
        case .onTarget: count += 1
        case .noData:   continue
        case .missed:   return count
        }
    }
    return count
}
