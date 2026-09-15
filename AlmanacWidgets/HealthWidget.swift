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

/// One look for every Home Screen widget: a periwinkle field with pale,
/// slightly translucent chips and navy ink on them, white text elsewhere.
enum WidgetPalette {
    static let field = Color(red: 0.36, green: 0.42, blue: 0.85)
    static let fieldDark = Color(red: 0.27, green: 0.31, blue: 0.66)
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.40)
    static let highlight = Color.white.opacity(0.30)
    static let secondary = Color.white.opacity(0.75)
    /// Lavender, sky, blush, butter, mint, peach.
    static let tints: [Color] = [
        Color(red: 0.93, green: 0.87, blue: 0.97),
        Color(red: 0.80, green: 0.86, blue: 0.98),
        Color(red: 0.96, green: 0.84, blue: 0.90),
        Color(red: 0.97, green: 0.93, blue: 0.78),
        Color(red: 0.85, green: 0.94, blue: 0.86),
        Color(red: 0.99, green: 0.88, blue: 0.80),
    ]
    static let chipOpacity = 0.92
}

struct WidgetCanvas: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        #if os(watchOS)
        Color.black
        #else
        (scheme == .dark ? WidgetPalette.fieldDark : WidgetPalette.field)
        #endif
    }
}

struct HealthWidgetView: View {
    let entry: HealthEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    private let orange = Color(red: 0.91, green: 0.36, blue: 0.16)
    private var onField: Bool {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge].contains(family)
        #else
        false
        #endif
    }
    @ViewBuilder var body: some View {
        // Accessory families are system-tinted, so only the field gets white.
        if onField { base.foregroundStyle(.white) } else { base }
    }
    @ViewBuilder private var base: some View {
        if entry.available, let snapshot = entry.snapshot { content(snapshot) }
        else { empty }
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
                Image(systemName: "sun.max.fill").widgetAccentable()
            }
            if family == .systemSmall {
                Spacer(minLength: 0)
                Text(data.steps.map { $0.formatted() } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).privacySensitive()
                Text("of \(data.stepGoal.formatted()) steps").font(.caption).foregroundStyle(WidgetPalette.secondary)
                ProgressView(value: data.stepProgress).tint(.white).privacySensitive()
            } else {
                HStack(spacing: 10) {
                    metric("Steps", value: data.steps.map { $0.formatted() } ?? "—", icon: "figure.walk", color: WidgetPalette.tints[5])
                    VStack(spacing: 8) {
                        metric("Sleep", value: data.sleepText, icon: "moon.fill", color: WidgetPalette.tints[0])
                        if family == .systemMedium {
                            Text("\(data.exerciseMinutes.map(String.init) ?? "—") min movement").font(.caption).privacySensitive()
                        } else {
                            metric("Movement", value: "\(data.exerciseMinutes.map(String.init) ?? "—") min", icon: "flame.fill", color: WidgetPalette.tints[3])
                        }
                    }
                }.frame(maxHeight: .infinity)
                if family != .systemMedium {
                    Link(destination: SurfaceRoute.activity.url) {
                        Label("Begin activity", systemImage: "plus")
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white, in: Capsule()).foregroundStyle(WidgetPalette.ink)
                    }
                }
            }
            if let date = data.measuredAt {
                Text("Updated \(date, style: .time)").font(.system(size: 10)).foregroundStyle(WidgetPalette.secondary)
            } else { Text("Open Almanac to sync").font(.caption2).foregroundStyle(WidgetPalette.secondary) }
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
        .padding(12).foregroundStyle(WidgetPalette.ink)
        .background(color.opacity(WidgetPalette.chipOpacity), in: RoundedRectangle(cornerRadius: 18))
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
                Image(systemName: "sun.max.fill").widgetAccentable()
                Text("A little closer to your day.").font(.headline)
                Text("Open Almanac to sign in or refresh your health data.")
                    .font(.caption).foregroundStyle(WidgetPalette.secondary)
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
