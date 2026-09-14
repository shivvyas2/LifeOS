import ActivityKit
import SwiftUI
import WidgetKit
import AppSurfaces
import DesignSystem

/// The lock screen and Dynamic Island for a running activity. Widget
/// extensions cannot render materials, so the "glass" tiles are translucent
/// white over the live gradient with a hairline edge.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(name: context.attributes.name, icon: context.attributes.icon, readout: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(SurfaceRoute.activity.url)
        } dynamicIsland: { context in
            let readout = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.name, systemImage: context.attributes.icon)
                        .font(.headline).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutTimer(readout: readout).font(.system(.title2, design: .rounded, weight: .bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 14) {
                            IslandReading(symbol: "heart.fill", value: readout.heartRate.map(String.init), unit: readout.zone.map { "Z\($0)" }, tint: readout.push.tint)
                            IslandReading(symbol: "bolt.fill", value: readout.effort.map { String(format: "%.1f", $0) }, unit: "est", tint: .white)
                            IslandReading(symbol: "flame.fill", value: readout.calories.map(String.init), unit: "kcal", tint: .white)
                            IslandReading(symbol: "battery.75percent", value: readout.batteryPercent.map { "\($0)%" }, unit: "left", tint: .white)
                        }
                        HStack {
                            Text(readout.isPaused ? "Paused" : readout.push.headline).foregroundStyle(.secondary)
                            Spacer()
                            Link("Open activity", destination: SurfaceRoute.activity.url).foregroundStyle(readout.push.tint)
                        }.font(.subheadline)
                    }.padding(.top, 6)
                }
            } compactLeading: {
                if let bpm = readout.heartRate {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.caption2)
                        Text("\(bpm)").font(.caption.monospacedDigit().weight(.semibold))
                    }.foregroundStyle(readout.push.tint)
                } else {
                    Image(systemName: context.attributes.icon).foregroundStyle(readout.push.tint)
                }
            } compactTrailing: {
                WorkoutTimer(readout: readout).font(.caption.monospacedDigit()).frame(width: 48)
            } minimal: {
                if let zone = readout.zone {
                    Text("\(zone)").font(.caption2.bold()).foregroundStyle(.black)
                        .frame(width: 18, height: 18).background(readout.push.tint, in: Circle())
                } else {
                    Image(systemName: readout.isPaused ? "pause.fill" : context.attributes.icon).foregroundStyle(readout.push.tint)
                }
            }
            .widgetURL(SurfaceRoute.activity.url)
            .keylineTint(readout.push.tint)
        }
    }
}

private struct LockScreenView: View {
    let name: String
    let icon: String
    let readout: LiveSessionReadout

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44).background(.white.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(readout.isPaused ? "Paused" : readout.push.headline).font(.caption)
                        .foregroundStyle(readout.push == .overLimit || readout.push == .nearLimit ? readout.push.tint : .white.opacity(0.85))
                }
                Spacer(minLength: 6)
                WorkoutTimer(readout: readout).font(.system(.title, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .foregroundStyle(.white)
            HStack(spacing: 8) {
                Tile(eyebrow: readout.zone.map { "Z\($0)" } ?? "BPM", value: readout.heartRate.map(String.init), symbol: "heart.fill")
                Tile(eyebrow: readout.ceilingTarget.map { "EST of \(Int($0.upperBound))" } ?? "EST", value: readout.effort.map { String(format: "%.1f", $0) }, symbol: "bolt.fill")
                Tile(eyebrow: "KCAL", value: readout.calories.map(String.init), symbol: "flame.fill")
                Tile(eyebrow: "LEFT", value: readout.batteryPercent.map { "\($0)%" }, symbol: "battery.75percent", ring: readout.batteryPercent)
            }
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(colors: [LifeOSTokens.liveGradientTop, LifeOSTokens.liveGradientBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.2), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            }
        }
    }
}

private struct Tile: View {
    let eyebrow: String
    let value: String?
    let symbol: String
    var ring: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2)
                Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(0.4)
            }.opacity(0.75)
            HStack(spacing: 6) {
                Text(value ?? "\u{2014}").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let ring {
                    Circle().trim(from: 0, to: CGFloat(ring) / 100).stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 14, height: 14)
                        .background(Circle().stroke(.white.opacity(0.25), lineWidth: 3))
                }
            }
        }
        .foregroundStyle(Color(white: 0.12))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.5))
        .privacySensitive()
    }
}

private struct IslandReading: View {
    let symbol: String
    let value: String?
    let unit: String?
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(tint)
            Text(value ?? "\u{2014}").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
            if let unit, value != nil { Text(unit).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

private struct WorkoutTimer: View {
    let readout: LiveSessionReadout
    var body: some View {
        if let anchor = readout.timerAnchor {
            Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
                .monospacedDigit().contentTransition(.numericText()).privacySensitive()
        } else {
            Text(Duration.seconds(readout.elapsed).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit().privacySensitive()
        }
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
