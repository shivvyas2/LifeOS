import SwiftUI
import AppSurfaces
import DesignSystem

/// The live readings as glass rings: heart rate against today's ceiling zone,
/// effort against the target band, battery as it stands, and a rep count for
/// strength. Made to sit over a video or a gradient, so it is always white on
/// glass. Tap the rings to fold the whole thing into one thin bar with the
/// clock and the pulse, for when the video matters more than the numbers.
struct SessionRings: View {
    let readout: LiveSessionReadout
    let activity: ActivityType
    let zonesAvailable: Bool
    /// Only a watch session counts reps by itself; on the phone every rep is
    /// a tap, and calling that "auto" would invert the honesty label.
    var countsAutomatically: Bool = false
    var onAddRep: () -> Void = {}
    var onRemoveRep: () -> Void = {}
    var onNextSet: () -> Void = {}
    /// Off when the screen puts the rep buttons somewhere with more room,
    /// as the portrait player does under the video.
    var showsRepControls = true
    /// Expanded shows the rings; collapsed is the bar.
    @Binding var isExpanded: Bool
    @Namespace private var glass
    /// Grows the rep count for a beat on every new rep.
    @State private var repPulse = false

    private var showsEffort: Bool { activity.showsZones && zonesAvailable }
    private var effortOver: Bool { SessionRingMath.effortIsOver(effort: readout.effort, target: readout.ceilingTarget) }
    private var shape: AnyShape {
        isExpanded ? AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous)) : AnyShape(Capsule())
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.snappy(duration: 0.35)) { isExpanded.toggle() } } label: {
                    Group { if isExpanded { rings } else { bar } }
                        .padding(.horizontal, isExpanded ? 16 : 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isExpanded, showsRepControls, activity.countsReps { repControls.padding(.horizontal, 16) }
            }
            .padding(.vertical, isExpanded ? 10 : 8)
            .foregroundStyle(.white)
            // A dark wash under the glass, so white reads over a bright frame
            // of video or the pale foot of the hero gradient alike.
            .background(shape.fill(.black.opacity(0.30)))
            .glassEffect(.regular.tint(readout.push.tint.opacity(0.25)).interactive(), in: shape)
            .glassEffectID("rings", in: glass)
        }
        .animation(.spring(duration: 0.6, bounce: 0.25), value: readout.heartRate)
        .animation(.spring(duration: 0.6, bounce: 0.25), value: readout.effort)
        .animation(.spring(duration: 0.6, bounce: 0.25), value: readout.batteryPercent)
        .onChange(of: readout.reps) { old, new in
            guard let old, let new, new > old else { return }
            withAnimation(.spring(duration: 0.25, bounce: 0.5)) { repPulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.spring(duration: 0.3)) { repPulse = false }
            }
        }
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityLabel(isExpanded ? "" : summary)
        .accessibilityHint(isExpanded ? "Double tap to show only the clock" : "Double tap for the rings")
    }

    // MARK: Rings

    private var rings: some View {
        HStack(alignment: .top, spacing: 10) {
            ring(fill: SessionRingMath.heartFill(zone: readout.zone, ceilingMaxZone: readout.ceilingMaxZone),
                 tint: readout.push.tint, value: readout.heartRateText, label: readout.zoneText ?? "bpm") {
                pulsingHeart
            }
            if showsEffort {
                ring(fill: SessionRingMath.effortFill(effort: readout.effort, target: readout.ceilingTarget),
                     tint: effortOver ? LifeOSTokens.pushOver : LifeOSTokens.pushNear,
                     value: readout.effortText, label: effortOver ? "over" : "effort") {
                    Image(systemName: "bolt.fill").symbolEffect(.bounce, value: effortOver)
                }
                ring(fill: SessionRingMath.batteryFill(percent: readout.batteryPercent),
                     tint: LifeOSTokens.pushEasy, value: readout.batteryText, label: "battery") {
                    Image(systemName: "battery.75percent")
                }
            }
            if activity.countsReps { repCount }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary)
    }

    private func ring<Icon: View>(fill: Double, tint: Color, value: String?, label: String,
                                  @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.6), radius: 4)
                VStack(spacing: 0) {
                    icon().font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                    Text(value ?? LiveSessionReadout.missing)
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                }
                .padding(6)
            }
            .frame(width: 46, height: 46)
            Text(label).font(LifeOSType.eyebrow).opacity(0.9).lineLimit(1)
        }
        .frame(width: 50)
    }

    /// One beat per beat: a scale wave at the live tempo, still when there
    /// is no reading to keep time to.
    private var pulsingHeart: some View {
        TimelineView(.animation(paused: SessionRingMath.beatPeriod(bpm: readout.heartRate) == nil || readout.isPaused)) { timeline in
            let period = SessionRingMath.beatPeriod(bpm: readout.heartRate) ?? 1
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let beat = max(0, sin(phase * .pi * 2))
            Image(systemName: "heart.fill").scaleEffect(1 + 0.35 * beat)
        }
    }

    private var repCount: some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                Text(readout.repsText ?? LiveSessionReadout.missing)
                    .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .scaleEffect(repPulse ? 1.35 : 1)
                Text(countsAutomatically ? "auto" : "reps").font(LifeOSType.eyebrow).opacity(0.9)
            }
            .frame(width: 46, height: 46)
            Text(readout.setText ?? "Set 1").font(LifeOSType.eyebrow).opacity(0.9).lineLimit(1)
        }
        .frame(width: 50)
    }

    var repControls: some View {
        HStack(spacing: 8) {
            Button("−1", action: onRemoveRep).accessibilityLabel("Remove one rep")
            Button("+1", action: onAddRep).accessibilityLabel("Add one rep")
            Button("Next set", action: onNextSet)
        }
        .font(LifeOSType.label)
        .buttonStyle(.glass)
        .tint(.white)
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 10) {
            timer
            pulsingHeart.font(.caption).foregroundStyle(readout.push.tint)
            Text(readout.heartRateText ?? LiveSessionReadout.missing)
                .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
            if activity.countsReps, let reps = readout.repsText {
                Text("· \(reps) reps").font(.subheadline.weight(.medium)).opacity(0.85)
            }
        }
        .frame(minHeight: 28)
    }

    private var timer: some View {
        Group {
            if let anchor = readout.timerAnchor {
                Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
            } else {
                Text(Duration.seconds(readout.elapsed).formatted(.time(pattern: .minuteSecond)))
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1)
    }

    private var summary: String {
        var parts = ["Elapsed \(Duration.seconds(readout.elapsed).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))"]
        if let bpm = readout.heartRate { parts.append("heart rate \(bpm)") }
        if let zone = readout.zone { parts.append("zone \(zone)") }
        if showsEffort, let effort = readout.effort { parts.append(String(format: "effort %.1f estimated", effort)) }
        if showsEffort, let battery = readout.batteryPercent { parts.append("battery \(battery) percent") }
        if activity.countsReps, let reps = readout.reps { parts.append("\(reps) reps in set \(readout.setIndex ?? 1)") }
        return parts.joined(separator: ", ")
    }
}

extension PushState {
    var tint: Color {
        switch self {
        case .easy, .onTrack: LifeOSTokens.pushEasy
        case .nearLimit: LifeOSTokens.pushNear
        case .overLimit: LifeOSTokens.pushOver
        }
    }
}

#Preview("Rings and bar") {
    struct Host: View {
        @State private var expanded = true
        @State private var collapsed = false
        var readout: LiveSessionReadout {
            var value = LiveSessionReadout(elapsed: 724, runningSince: .now, push: .nearLimit)
            value.heartRate = 152; value.zone = 4; value.effort = 9.3; value.calories = 210; value.reps = 7; value.setIndex = 2
            value.batteryPercent = 62; value.capacitySource = "whoop"; value.ceilingMaxZone = 4; value.ceilingTarget = 10...14
            return value
        }
        var body: some View {
            ZStack {
                LinearGradient(colors: [.black, .indigo], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    SessionRings(readout: readout, activity: ActivityCatalog.strength, zonesAvailable: true, countsAutomatically: true, isExpanded: $expanded)
                    SessionRings(readout: readout, activity: ActivityCatalog.run, zonesAvailable: true, isExpanded: $collapsed)
                }.padding()
            }
        }
    }
    return Host()
}
