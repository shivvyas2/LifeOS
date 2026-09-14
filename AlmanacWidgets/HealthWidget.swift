import SwiftUI
import WidgetKit
import AppSurfaces

struct HealthEntry: TimelineEntry {
    let date: Date
    let snapshot: SurfaceSnapshot?
    var available: Bool { snapshot?.isAvailable(at: date) == true }
}

struct HealthTimeline: TimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        HealthEntry(date: .now, snapshot: SurfaceSnapshot(ownerID: "preview", measuredAt: .now,
            steps: 6240, sleepMinutes: 452, exerciseMinutes: 24))
    }
    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : HealthEntry(date: .now, snapshot: .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let now = Date.now
        let snapshot = SurfaceSnapshot.read()
        var entries = [HealthEntry(date: now, snapshot: snapshot)]
        // Explicit expiry entry hides yesterday's data even when refresh is delayed.
        if let snapshot, snapshot.expiresAt > now {
            entries.append(HealthEntry(date: snapshot.expiresAt, snapshot: nil))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}

struct HealthWidget: Widget {
    let kind = "AlmanacHealth"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthTimeline()) { entry in
            HealthWidgetView(entry: entry)
                .widgetURL(SurfaceRoute.health.url)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Your day")
        .description("Steps, sleep and movement from your connected health sources.")
        .supportedFamilies(families)
    }
    private var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
         .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct WidgetCanvas: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        #if os(watchOS)
        Color.black
        #else
        (scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.97, green: 0.95, blue: 0.91))
        #endif
    }
}

struct HealthWidgetView: View {
    let entry: HealthEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    private let orange = Color(red: 0.91, green: 0.36, blue: 0.16)
    var body: some View {
        Group {
            if entry.available, let snapshot = entry.snapshot { content(snapshot) }
            else { empty }
        }
    }
    @ViewBuilder private func content(_ data: SurfaceSnapshot) -> some View {
        switch family {
        case .accessoryInline:
            Label("\(data.steps.map { $0.formatted() } ?? "—") steps · \(data.sleepText)", systemImage: "figure.walk")
                .privacySensitive()
        case .accessoryCircular:
            Gauge(value: data.stepProgress) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(data.steps.map { $0.formatted(.number.notation(.compactName)) } ?? "—")
            }.gaugeStyle(.accessoryCircular).tint(orange).privacySensitive()
                .accessibilityLabel("\(data.steps.map(String.init) ?? "No") steps of \(data.stepGoal)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("Almanac", systemImage: "sun.max.fill").font(.headline).widgetAccentable()
                Text("\(data.steps.map { $0.formatted() } ?? "—") steps · \(data.sleepText)")
                    .font(.system(.body, weight: .semibold)).minimumScaleFactor(0.8).privacySensitive()
                if let date = data.measuredAt {
                    Text("Updated \(date, style: .time)").font(.caption2).foregroundStyle(.secondary)
                } else { Text("Open Almanac to sync").font(.caption2) }
            }
        default:
            #if os(iOS)
            home(data)
            #else
            empty
            #endif
        }
    }
    #if os(iOS)
    @ViewBuilder private func home(_ data: SurfaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(.system(.headline, weight: .bold))
                Spacer()
                Image(systemName: "sun.max.fill").foregroundStyle(orange).widgetAccentable()
            }
            if family == .systemSmall {
                Spacer(minLength: 0)
                Text(data.steps.map { $0.formatted() } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).privacySensitive()
                Text("of \(data.stepGoal.formatted()) steps").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: data.stepProgress).tint(orange).privacySensitive()
            } else {
                HStack(spacing: 10) {
                    metric("Steps", value: data.steps.map { $0.formatted() } ?? "—", icon: "figure.walk", color: Color(red: 1, green: 0.80, blue: 0.66))
                    VStack(spacing: 8) {
                        metric("Sleep", value: data.sleepText, icon: "moon.fill", color: Color(red: 0.84, green: 0.81, blue: 0.97))
                        if family == .systemMedium {
                            Text("\(data.exerciseMinutes.map(String.init) ?? "—") min movement").font(.caption).privacySensitive()
                        } else {
                            metric("Movement", value: "\(data.exerciseMinutes.map(String.init) ?? "—") min", icon: "flame.fill", color: Color(red: 0.82, green: 0.90, blue: 0.70))
                        }
                    }
                }.frame(maxHeight: .infinity)
                if family != .systemMedium {
                    Link(destination: SurfaceRoute.activity.url) {
                        Label("Begin activity", systemImage: "plus")
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(orange, in: Capsule()).foregroundStyle(.white)
                    }
                }
            }
            if let date = data.measuredAt {
                Text("Updated \(date, style: .time)").font(.system(size: 10)).foregroundStyle(.secondary)
            } else { Text("Open Almanac to sync").font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func metric(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon).font(.caption.weight(.medium))
            Spacer(minLength: 0)
            Text(value).font(.system(size: family == .systemMedium ? 22 : 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65).lineLimit(1).monospacedDigit().privacySensitive()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12).foregroundStyle(Color(white: 0.12))
        .background(color, in: RoundedRectangle(cornerRadius: 18))
    }
    #endif
    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryInline: Label("Open Almanac to sync", systemImage: "sun.max")
        case .accessoryCircular: Image(systemName: "sun.max").font(.title)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Label("Almanac", systemImage: "sun.max").font(.headline)
                Text("Open the app to sync your day.").font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sun.max.fill").foregroundStyle(orange).widgetAccentable()
                Text("A little closer to your day.").font(.headline)
                Text("Open Almanac to sign in or refresh your health data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct BeginActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AlmanacBeginActivity", provider: HealthTimeline()) { _ in
            BeginActivityWidgetView()
                .widgetURL(SurfaceRoute.activity.url)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Begin activity")
        .description("Open your activity timer with one tap.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
struct BeginActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if family == .accessoryCircular {
            Image(systemName: "figure.run.circle.fill").font(.largeTitle).widgetAccentable()
                .accessibilityLabel("Begin activity in Almanac")
        } else {
            Label { VStack(alignment: .leading) {
                Text("Begin activity").font(.headline)
                Text("Make a little move.").font(.caption)
            } } icon: { Image(systemName: "figure.run").font(.title2).widgetAccentable() }
        }
    }
}
