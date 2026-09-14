#if DEBUG && SURFACE_DESIGN_PREVIEW
import SwiftUI
import SwiftData
import WidgetKit
import AppSurfaces
import Persistence
import DesignSystem

/// An isolated simulator harness; enabled only by the design-preview build flag.
struct SurfaceDesignPreview: View {
    private let container: ModelContainer
    private let snapshot = SurfaceSnapshot(ownerID: "surface-preview", measuredAt: .now, steps: 6240,
        sleepMinutes: 452, exerciseMinutes: 24)
    @State private var recorder: ActivityRecorder
    @State private var route = ""
    private var page: String { ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--page=") }?.replacingOccurrences(of: "--page=", with: "") ?? "gallery" }
    init() {
        container = try! LifeOSContainer.make(inMemory: true)
        try! MetricsStore(context: container.mainContext).upsert(date: .now) { $0.steps = 6240; $0.sleepMinutes = 452; $0.exerciseMinutes = 24 }
        let defaults = UserDefaults(suiteName: "almanac.surface.design")!
        recorder = ActivityRecorder(defaults: defaults)
        recorder.saveToHealth = false
    }
    var body: some View {
        Group {
            switch page {
            case "checks": Text("Running native surface checks…").task {
                let report = SurfaceNativeChecks.run().joined(separator: "\n")
                let file = URL.documentsDirectory.appendingPathComponent("surface-checks.txt")
                try? report.write(to: file, atomically: true, encoding: .utf8)
            }
            case "inbox": NavigationStack { NotificationInboxScreen() }
            case "settings": NavigationStack { SurfaceSettingsScreen() }
            case "activity": BeginActivityScreen(model: recorder)
            default: gallery
            }
        }
        .modelContainer(container)
        .onOpenURL { route = $0.absoluteString }
        .task {
            if page == "activity" { recorder.attach(container.mainContext) }
            else { WorkoutLiveActivityController.endAll() }
            SurfaceCoordinator.shared.adopt(ownerID: "surface-preview", context: container.mainContext)
            PushService.shared.attach(ownerID: "surface-preview")
            _ = PushService.shared.receive(InboxEntry(ownerID: "surface-preview", text: "You’ve made room for movement today. A gentle wind-down could help you settle into the evening.", trigger: "rest", day: "2026-09-14", receivedAt: .now))
            _ = PushService.shared.receive(InboxEntry(ownerID: "surface-preview", text: "A short walk is a good place to start. Pick a time that feels easy to keep.", trigger: "movement", day: "2026-09-13", receivedAt: .now.addingTimeInterval(-86400), isRead: true))
        }
    }
    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your day, closer.").font(LifeOSType.display)
                Text("Almanac · Home & Lock Screen").font(LifeOSType.secondary).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    preview(.systemSmall, width: 164, height: 164)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("A small step.").font(LifeOSType.sectionTitle)
                        Text("A clear glance at your day.").font(LifeOSType.secondary).foregroundStyle(.secondary)
                    }
                }
                preview(.systemMedium, width: 348, height: 164)
                HStack {
                    HealthWidgetView(entry: HealthEntry(date: .now, snapshot: snapshot), previewFamily: .accessoryRectangular)
                    Spacer()
                    HealthWidgetView(entry: HealthEntry(date: .now, snapshot: snapshot), previewFamily: .accessoryCircular).frame(width: 64, height: 64)
                }.padding(20).background(.black, in: RoundedRectangle(cornerRadius: 24)).foregroundStyle(.white)
                preview(.systemLarge, width: 348, height: 364)
                Text(route).font(.caption)
            }.frame(maxWidth: 348).frame(maxWidth: .infinity).padding(22)
        }.background(Color(white: 0.90))
    }
    private func preview(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        HealthWidgetView(entry: HealthEntry(date: .now, snapshot: snapshot), previewFamily: family)
            .padding(16).frame(width: width, height: height)
            .background { WidgetCanvas() }.clipShape(RoundedRectangle(cornerRadius: 26))
    }
}
#endif
