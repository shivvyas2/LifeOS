import SwiftUI

/// One night's sleep broken into its stages.
///
/// This is the view that justifies ingesting the stages at all: a five hour
/// night and a fragmented seven hour night look identical on a duration chart
/// and obviously different once the structure is visible.
public struct SleepComposition: Sendable, Equatable, Identifiable {
    public enum Stage: Sendable, Equatable, CaseIterable {
        case sws, rem, light, awake

        public var label: String {
            switch self {
            case .sws:   "Deep"
            case .rem:   "REM"
            case .light: "Light"
            case .awake: "Awake"
            }
        }

        /// Deepest at the bottom, awake at the top. A fixed order lets two
        /// nights be compared by eye; ordering by size would not.
        public var color: Color {
            switch self {
            case .sws:   Color(red: 0.18, green: 0.28, blue: 0.62)
            case .rem:   Color(red: 0.36, green: 0.50, blue: 0.86)
            case .light: Color(red: 0.62, green: 0.73, blue: 0.94)
            case .awake: Color(white: 0.80)
            }
        }
    }

    public struct Segment: Sendable, Equatable, Identifiable {
        public let stage: Stage
        public let minutes: Int
        public var id: Stage { stage }
    }

    public let date: Date
    public let lightMinutes: Int?
    public let remMinutes: Int?
    public let swsMinutes: Int?
    public let awakeMinutes: Int?

    public var id: Date { date }

    public init(date: Date, lightMinutes: Int?, remMinutes: Int?,
                swsMinutes: Int?, awakeMinutes: Int?) {
        self.date = date
        self.lightMinutes = lightMinutes
        self.remMinutes = remMinutes
        self.swsMinutes = swsMinutes
        self.awakeMinutes = awakeMinutes
    }

    /// Only the stages actually reported, in stacking order. A stage Whoop did
    /// not report is absent rather than a zero segment.
    public var segments: [Segment] {
        [(Stage.sws, swsMinutes), (.rem, remMinutes), (.light, lightMinutes), (.awake, awakeMinutes)]
            .compactMap { stage, minutes in
                guard let minutes, minutes > 0 else { return nil }
                return Segment(stage: stage, minutes: minutes)
            }
    }

    /// Time in bed, which includes time awake. This is the bar's height.
    public var totalMinutes: Int {
        segments.reduce(0) { $0 + $1.minutes }
    }

    /// Time actually asleep. Awake time is part of the night but not part of
    /// sleep, and conflating them overstates every figure derived from it.
    public var asleepMinutes: Int {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.minutes }
    }

    /// A night with nothing recorded must be dropped from the chart. Drawing it
    /// as a zero-height bar reads as "you did not sleep", which is a claim the
    /// data does not make.
    public var isRenderable: Bool { !segments.isEmpty }
}
