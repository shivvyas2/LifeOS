import SwiftUI
import DesignSystem
import AppSurfaces
import Integrations

/// Where the live readings come from, and whether they are arriving: a dot
/// and a line at the top of the live hero. Green and pulsing when live,
/// amber when quiet, red when the watch has gone.
struct LiveLinkLine: View {
    let link: LiveLink
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dot: Color {
        switch link {
        case .watchLive, .sensorLive: LifeOSTokens.pushEasy
        case .watchQuiet, .sensorQuiet: LifeOSTokens.pushNear
        case .watchDisconnected: LifeOSTokens.pushOver
        case .noSource, .paused: .white.opacity(0.5)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8)
                .scaleEffect(link.isLive && pulse ? 1.35 : 1)
                .opacity(link.isLive && pulse ? 0.6 : 1)
                .animation(link.isLive && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever() : nil, value: pulse)
            Text(link.title).font(LifeOSType.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.22), in: Capsule())
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(link.title)
    }
}

/// The session's readings as one ruled card, each with a picture of what
/// the number means rather than the number alone.
struct LiveReadings: View {
    let model: ActivityRecorder
    let readout: LiveSessionReadout
    let link: LiveLink
    let now: Date
    @Environment(\.colorScheme) private var scheme

    private var heartFresh: Bool {
        model.isRunning && model.heartRateDate.map { now.timeIntervalSince($0) < 15 } == true
    }

    var body: some View {
        VStack(spacing: 0) {
            heartRow
            if model.zonesAvailable, model.selection.showsZones { effortRow }
            if model.selection.name == ActivityRecorder.badminton { swingsRow }
            if model.selection.countsReps {
                plainRow(readout.setText ?? "Reps", value: readout.repsText, unit: "reps",
                         caption: model.completedSets.isEmpty
                            ? (model.source == .watch ? "Counted from your wrist" : "Tap +1 for each rep")
                            : "Earlier sets: \(model.completedSets.map(String.init).joined(separator: ", "))")
            }
            plainRow("Calories", value: readout.caloriesText, unit: "kcal",
                     caption: readout.calories == nil ? "No energy reading yet" : model.source == .demo ? "Simulated for the demo" : "From Apple Health")
            if model.selection.tracksDistance {
                plainRow("Distance", value: readout.distanceKilometresText, unit: "km",
                         caption: readout.distanceMeters == nil ? "No distance reading yet" : "From Apple Health", last: true)
            }
            if !model.zonesAvailable {
                Text("Add your birth date in Profile for zones, effort and battery.")
                    .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
        }
        .editorialCard(padding: 18)
    }

    // MARK: Rows

    private var heartRow: some View {
        row(label: "Heart rate", tag: heartFresh ? readout.zone.map { "Z\($0)" } : nil,
            value: heartFresh ? readout.heartRateText : nil, unit: "bpm",
            caption: heartFresh ? heartSource : (model.isPaused ? "Paused" : "No live reading · \(link.title)")) {
            ZoneBar(zone: heartFresh ? readout.zone : nil)
        }
    }

    private var heartSource: String {
        model.source == .watch ? "From Apple Watch"
            : model.source == .demo ? "Simulated for the demo"
            : model.sensor.connectedName.map { "From \($0)" } ?? "Live sensor"
    }

    private var effortRow: some View {
        row(label: "Effort", tag: nil, value: readout.effortText,
            unit: readout.ceilingTarget.map { "of \(Int($0.upperBound))" },
            caption: effortCaption) {
            EffortTrack(effort: readout.effort, target: readout.ceilingTarget, push: readout.push)
        }
    }

    private var effortCaption: String {
        guard let target = readout.ceilingTarget else { return "Battery unknown · cautious target" }
        let band = "Target \(Int(target.lowerBound))–\(Int(target.upperBound))"
        return readout.capacitySource == nil ? band : "\(band) · battery \(readout.batteryText ?? LiveSessionReadout.missing)"
    }

    private var swingsRow: some View {
        let pace = SwingPace.perMinute(model.swingMoments, now: now)
        return row(label: "Swings", tag: model.swingCount == nil ? nil : "\(pace)/min",
                   value: model.swingCount.map(String.init), unit: "candidates",
                   caption: swingCaption) {
            SwingPaceBar(perMinute: model.swingCount == nil ? nil : pace)
        }
    }

    private var swingCaption: String {
        guard model.swingCount != nil else { return "Turn on swing analysis and wear the watch on your racket wrist" }
        let peak = model.peakWristRotation.map { "peak \(Int(($0 * 180 / .pi).rounded()))°/s at the wrist" }
        return [model.source == .demo ? "Simulated for the demo" : "Estimated", peak].compactMap { $0 }.joined(separator: " · ")
    }

    private func plainRow(_ label: String, value: String?, unit: String?, caption: String, last: Bool = false) -> some View {
        row(label: label, tag: nil, value: value, unit: unit, caption: caption, last: last) { EmptyView() }
    }

    /// Label and tag on the left, the figure large and light on the right,
    /// the picture under them, a caption saying where it came from.
    private func row<Picture: View>(label: String, tag: String?, value: String?, unit: String?, caption: String,
                                    last: Bool = false, @ViewBuilder picture: () -> Picture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Text(label).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                if let tag { EditorialTag(tag) }
                Spacer(minLength: Space.x1)
                Text(value ?? LiveSessionReadout.missing)
                    .font(Editorial.figure(40)).tracking(Editorial.figureTracking(40)).monospacedDigit()
                    .opacity(value == nil ? 0.35 : 1)
                    .contentTransition(.numericText())
                if let unit, value != nil {
                    Text(unit).font(LifeOSType.label).foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            picture()
            Text(caption).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
        .accessibilityElement(children: .combine)
    }
}

/// Five steps, the current zone filled in ink, the ones below it outlined
/// and tinted, so "Z4" reads as four-fifths of the way up at a glance.
struct ZoneBar: View {
    let zone: Int?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { step in
                let ink = LifeOSTokens.primaryText.resolve(scheme)
                RoundedRectangle(cornerRadius: 3)
                    .fill(zone == step ? ink : (zone.map { step < $0 } == true ? ink.opacity(0.25) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Editorial.rule(scheme)))
                    .overlay {
                        Text("Z\(step)").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(zone == step ? LifeOSTokens.canvas.resolve(scheme) : Editorial.quietInk(scheme))
                    }
                    .frame(height: 18)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Effort on a track: the target band shaded, a marker where the session
/// is, so "inside the band", "short of it" and "past it" are all visible
/// without reading two numbers and comparing them.
struct EffortTrack: View {
    let effort: Double?
    let target: ClosedRange<Double>?
    let push: PushState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let top = max((target?.upperBound ?? 10) * 1.25, (effort ?? 0) * 1.05, 1)
            let x = { (value: Double) in proxy.size.width * min(max(value / top, 0), 1) }
            ZStack(alignment: .leading) {
                Capsule().fill(Editorial.rule(scheme)).frame(height: 6)
                if let target {
                    Capsule().fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.18))
                        .frame(width: max(x(target.upperBound) - x(target.lowerBound), 4), height: 14)
                        .offset(x: x(target.lowerBound))
                }
                if let effort {
                    Capsule().fill(push.tint).frame(width: x(effort), height: 6)
                    Circle().fill(LifeOSTokens.primaryText.resolve(scheme)).frame(width: 14, height: 14)
                        .offset(x: x(effort) - 7)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

/// Swings in the last minute against a busy rally's pace, so a hard
/// exchange and a breather look different.
struct SwingPaceBar: View {
    let perMinute: Int?
    /// About one swing every two seconds is a full-out rally.
    private let busy = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<busy, id: \.self) { index in
                Rectangle()
                    .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(index < (perMinute ?? 0) ? 0.85 : 0.12))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
