import SwiftUI

/// One night's sleep broken into its stages.
///
/// This is the view that justifies ingesting the stages at all: a five hour
/// night and a fragmented seven hour night look identical on a duration chart
/// and obviously different once the structure is visible.
public struct SleepComposition: Sendable, Equatable, Identifiable {
    public enum Stage: Sendable, Equatable, Hashable, CaseIterable {
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
            case .sws:   Color(red: 0.10, green: 0.28, blue: 0.86)
            case .rem:   Color(red: 0.22, green: 0.48, blue: 0.98)
            case .light: Color(red: 0.38, green: 0.68, blue: 1.00)
            case .awake: Color(red: 0.42, green: 0.52, blue: 0.78)
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

    /// Light → REM → Deep, left to right. Awake is a quality fact, not a
    /// stage of sleep, so it does not belong on the score bar.
    public var scoreBarSegments: [Segment] {
        [(Stage.light, lightMinutes), (.rem, remMinutes), (.sws, swsMinutes)]
            .compactMap { stage, minutes in
                guard let minutes, minutes > 0 else { return nil }
                return Segment(stage: stage, minutes: minutes)
            }
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

/// Horizontal Light → REM → Deep bar. Widths follow the minutes; colours are
/// the solid stage colours, never a wash.
public struct SleepStageBar: View {
    public let segments: [SleepComposition.Segment]
    public var height: CGFloat
    public var showsLabels: Bool

    public init(segments: [SleepComposition.Segment], height: CGFloat = 16, showsLabels: Bool = true) {
        self.segments = segments
        self.height = height
        self.showsLabels = showsLabels
    }

    private var total: Int {
        max(segments.reduce(0) { $0 + $1.minutes }, 1)
    }

    public var body: some View {
        let total = CGFloat(self.total)
        GeometryReader { geo in
            let gap = CGFloat(max(segments.count - 1, 0)) * 3
            let usable = max(geo.size.width - gap, 0)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(segments) { segment in
                    VStack(spacing: 6) {
                        if showsLabels {
                        Text(segment.stage.label)
                            .font(LifeOSType.eyebrow)
                            .foregroundStyle(segment.stage.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        }
                        Capsule()
                            .fill(segment.stage.color)
                            .frame(height: height)
                    }
                    .frame(width: max(usable * CGFloat(segment.minutes) / total, 4),
                           alignment: .bottom)
                }
            }
        }
        .frame(height: height + (showsLabels ? 22 : 0))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One column per night, Deep at the bottom. Separate columns, not one stacked
/// chart box, so two nights can be compared by eye.
public struct SleepNightStrip: View {
    public let nights: [SleepComposition]
    private let scale: Int
    @Environment(\.colorScheme) private var scheme

    public init(nights: [SleepComposition], maxMinutes: Int? = nil) {
        self.nights = nights
        self.scale = max(maxMinutes ?? nights.map(\.totalMinutes).max() ?? 1, 1)
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(nights) { night in
                VStack(spacing: 6) {
                    SleepNightColumn(night: night, scale: scale)
                    Text(night.date, format: .dateTime.weekday(.narrow))
                        .font(LifeOSType.eyebrow.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SleepNightColumn: View {
    let night: SleepComposition
    let scale: Int
    private let height: CGFloat = 132

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(night.segments.reversed())) { segment in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(segment.stage.color)
                    .frame(height: max(3, height * CGFloat(segment.minutes) / CGFloat(scale)))
            }
        }
        .frame(maxWidth: 18)
        .frame(maxWidth: .infinity)
    }
}
