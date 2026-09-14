import SwiftUI
import AppSurfaces
import DesignSystem

/// One glass capsule with the readings that matter right now. Tap to expand
/// into the ceiling line and the slower numbers. Adapts to the activity:
/// distance for movement, a reps slot for strength, no effort talk for yoga.
struct SessionHUD: View {
    let readout: LiveSessionReadout
    let activity: RecordedActivity
    let zonesAvailable: Bool
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) private var scheme
    @Namespace private var glass

    private var showsEffort: Bool { activity != .yoga && zonesAvailable }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        timer
                        reading(symbol: "heart.fill", value: readout.heartRate.map(String.init), chip: readout.zone.map { "Z\($0)" }, tint: readout.push.tint)
                        if showsEffort {
                            reading(symbol: "bolt.fill", value: readout.effort.map { String(format: "%.1f", $0) }, chip: "est", tint: nil)
                            reading(symbol: "battery.75percent", value: readout.batteryPercent.map { "\($0)%" }, chip: nil, tint: nil)
                        }
                        if activity == .strength {
                            reading(symbol: "repeat", value: nil, chip: "reps", tint: nil)
                        }
                    }
                    if isExpanded { expanded }
                }
                .padding(.horizontal, 18).padding(.vertical, isExpanded ? 14 : 10)
                .frame(minHeight: 52)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(readout.push.tint.opacity(0.18)).interactive(),
                         in: isExpanded ? AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) : AnyShape(Capsule()))
            .glassEffectID("hud", in: glass)
        }
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityLabel(isExpanded ? "" : summary)
        .accessibilityHint(isExpanded ? "" : "Double tap for today's ceiling and calories")
    }

    private var timer: some View {
        Group {
            if let anchor = readout.timerAnchor {
                Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
            } else {
                Text(Duration.seconds(readout.elapsed).formatted(.time(pattern: .minuteSecond)))
            }
        }
        .font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }

    private func reading(symbol: String, value: String?, chip: String?, tint: Color?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint ?? LifeOSTokens.secondaryText.resolve(scheme))
            Text(value ?? "\u{2014}").font(.headline).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            if let chip {
                Text(chip).font(LifeOSType.eyebrow).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
        }.lineLimit(1)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ceilingLine).font(LifeOSType.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            HStack(spacing: 16) {
                reading(symbol: "flame.fill", value: readout.calories.map(String.init), chip: "kcal", tint: nil)
                if [.walk, .run, .cycle].contains(activity) {
                    reading(symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                            value: readout.distanceMeters.map { String(format: "%.2f", Double($0) / 1000) }, chip: "km", tint: nil)
                }
                if readout.push == .overLimit { Text("Over your target").font(LifeOSType.label).foregroundStyle(LifeOSTokens.pushNear) }
            }
        }
    }

    private var ceilingLine: String {
        if activity == .yoga { return "Recovery session" }
        guard zonesAvailable else { return "Add your birth date in Profile for zones and effort." }
        let source = switch readout.capacitySource {
            case "whoop": "WHOOP recovery"
            case "health": "Apple Health"
            default: "Battery unknown"
        }
        guard let zone = readout.ceilingMaxZone, let target = readout.ceilingTarget else { return source }
        return "Up to zone \(zone) today · target \(Int(target.lowerBound)) to \(Int(target.upperBound)) · \(source)"
    }

    private var summary: String {
        var parts = ["Elapsed \(Duration.seconds(readout.elapsed).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))"]
        if let bpm = readout.heartRate { parts.append("heart rate \(bpm)") }
        if let zone = readout.zone { parts.append("zone \(zone)") }
        if showsEffort, let effort = readout.effort { parts.append(String(format: "effort %.1f estimated", effort)) }
        if showsEffort, let battery = readout.batteryPercent { parts.append("battery \(battery) percent") }
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

#Preview("Collapsed and expanded") {
    struct Host: View {
        @State private var expanded = false
        @State private var expandedTwo = true
        var readout: LiveSessionReadout {
            var value = LiveSessionReadout(elapsed: 724, runningSince: .now, push: .nearLimit)
            value.heartRate = 152; value.zone = 4; value.effort = 9.3; value.calories = 210
            value.batteryPercent = 62; value.capacitySource = "whoop"; value.ceilingMaxZone = 4; value.ceilingTarget = 10...14
            return value
        }
        var body: some View {
            ZStack {
                LinearGradient(colors: [LifeOSTokens.liveGradientTop, LifeOSTokens.liveGradientBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 24) {
                    SessionHUD(readout: readout, activity: .run, zonesAvailable: true, isExpanded: $expanded)
                    SessionHUD(readout: readout, activity: .strength, zonesAvailable: true, isExpanded: $expandedTwo)
                    SessionHUD(readout: LiveSessionReadout(elapsed: 30, runningSince: nil, push: .onTrack), activity: .yoga, zonesAvailable: false, isExpanded: $expanded)
                }.padding()
            }
        }
    }
    return Host()
}
