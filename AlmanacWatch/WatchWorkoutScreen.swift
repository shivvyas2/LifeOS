import SwiftUI
import AppSurfaces

/// Metrics and controls occupy separate crown-scrollable pages, so a small
/// Watch never has to squeeze a pause target between live readings.
struct WatchWorkoutScreen: View {
    let workout: WatchWorkoutController
    @State private var page = 0
    @State private var confirmingEnd = false
    @Environment(\.isLuminanceReduced) private var dimmed
    private var accent: Color { WatchPalette.color(for: workout.activity ?? ActivityCatalog.other) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: dimmed ? 60 : 5)) { _ in
        TabView(selection: $page) {
            ScrollView {
                VStack(spacing: 8) {
                    hero
                    HStack(spacing: 7) {
                        metric("Heart rate", value: workout.freshHeartRate.map(String.init) ?? "—", unit: "BPM", icon: "heart.fill", color: .pink)
                        metric("Active energy", value: workout.energyKcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", unit: "KCAL", icon: "flame.fill", color: .orange)
                    }
                    if workout.layout == .strength { strength }
                    else if workout.layout == .distance { distance }
                    else if workout.activity?.showsZones == true { zone }
                    Text(workout.mirroringFailed ? "Recording on Watch · sync later" : "Live with iPhone")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button { page = 2 } label: { Label("Controls", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.glass).tint(.orange)
                }.padding(.horizontal, 2)
            }.tag(0)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your rhythm").font(.headline)
                    heartTrend
                    if workout.layout == .distance { distance }
                    if workout.layout == .strength { strength }
                    if workout.activity?.showsZones == true { zone }
                    Text(workout.layout == .mindful ? "Move at your own pace. Pause whenever you need." : "Heart rate comes from your Watch. Gaps mean a new reading is not available.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 2)
            }.tag(1)
            ScrollView {
                VStack(spacing: 10) {
                    Label(workout.activityName, systemImage: workout.activity?.symbol ?? "figure.run")
                        .font(.headline).foregroundStyle(accent)
                    timer.font(.system(size: 32, weight: .semibold, design: .rounded))
                    if let error = workout.lastError {
                        Text(error).font(.caption2).foregroundStyle(.orange)
                    }
                    if workout.state == .ending {
                        if workout.lastError != nil { Button("Retry save") { workout.retrySave() }.buttonStyle(.glassProminent).tint(.orange) }
                        else { ProgressView("Saving workout") }
                    } else {
                        Button { workout.state == .paused ? workout.resume() : workout.pause() } label: {
                            Label(workout.state == .paused ? "Resume" : "Pause", systemImage: workout.state == .paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.glassProminent).tint(.orange)
                        Button { confirmingEnd = true } label: {
                            Label("Finish & save", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.glass)
                        if workout.isStrength { repControls }
                    }
                    Label("Recorded on Apple Watch", systemImage: "applewatch")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Keep going without your phone. Your workout is saved to Health on this Watch.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal, 4)
            }.tag(2)
        }
        .tabViewStyle(.page)
        .navigationTitle(workout.activityName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Finish this workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("Finish & save") { workout.end() }
            Button("Keep going", role: .cancel) {}
        }
        .onChange(of: workout.state) { _, state in if state == .ending { page = 2 } }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--design-preview"),
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--watch-page=") }),
               let requested = Int(argument.dropFirst("--watch-page=".count)), (0...2).contains(requested) { page = requested }
            #endif
        }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                activitySymbol(workout.activity?.symbol ?? "figure.run").font(.system(size: 18))
                Spacer()
                Text(workout.state == .paused ? "Paused" : heroLabel).font(.system(size: 9, weight: .semibold)).textCase(.uppercase).tracking(1)
            }.foregroundStyle(accent)
            timer.font(.system(size: 32, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.65).lineLimit(1)
            if workout.layout == .court { court.frame(height: 14).accessibilityHidden(true) }
            else { Text(workout.state == .paused ? "Paused" : "Active time").font(.caption2).foregroundStyle(.white.opacity(0.65)) }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background { WatchTileBackground(color: accent, dimmed: dimmed) }
        .accessibilityElement(children: .combine)
    }
    private var heroLabel: String {
        switch workout.layout {
        case .court: return "On court"
        case .strength: return "Set \(workout.setIndex ?? 1)"
        case .mindful: return "Take your time"
        case .distance: return "In motion"
        case .general: return "Your session"
        }
    }
    @ViewBuilder private var timer: some View {
        if let since = workout.runningSince, workout.state == .running {
            Text(timerInterval: since.addingTimeInterval(-workout.accumulated)...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else if workout.state == .starting { Text("Starting…") }
        else { Text(Duration.seconds(workout.accumulated).formatted(.time(pattern: .minuteSecond))).monospacedDigit() }
    }
    private var court: some View {
        GeometryReader { geometry in
            Path { path in
                let rect = CGRect(x: 1, y: 1, width: geometry.size.width - 2, height: geometry.size.height - 2)
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
                path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                for fraction in [0.25, 0.75] {
                    let x = rect.width * fraction
                    path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                path.move(to: CGPoint(x: rect.minX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }.stroke(accent.opacity(0.65), lineWidth: 1)
        }
    }
    private func metric(_ title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon).foregroundStyle(color)
                Text(unit).foregroundStyle(.white.opacity(0.65))
            }.font(.system(size: 9, weight: .medium))
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
            .background { WatchTileBackground(color: color, dimmed: dimmed) }
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(value) \(unit)")
    }
    private var strength: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(workout.reps.map(String.init) ?? "—") reps").font(.title3.bold()).monospacedDigit()
                Text("Wrist estimate · adjust in Controls").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text("SET\n\(workout.setIndex ?? 1)").font(.caption2.bold()).multilineTextAlignment(.center).foregroundStyle(accent)
        }.padding(10).background { WatchTileBackground(color: accent, dimmed: dimmed) }
    }
    private var repControls: some View {
        VStack(spacing: 8) {
            Text("\(workout.reps.map(String.init) ?? "—") reps · set \(workout.setIndex ?? 1)").font(.headline)
            HStack {
                Button("−1") { workout.removeRep() }.accessibilityLabel("Remove one rep")
                Button("+1") { workout.addRep() }.accessibilityLabel("Add one rep")
            }.buttonStyle(.glass)
            Button("Next set") { workout.nextSet() }.buttonStyle(.glass)
        }
    }
    private var distance: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Distance").font(.caption2).foregroundStyle(.secondary)
                Text(workout.distanceMeters.map { ($0 / 1000).formatted(.number.precision(.fractionLength(2))) + " km" } ?? "—")
                    .font(.headline).monospacedDigit()
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(paceLabel).font(.caption2).foregroundStyle(.secondary)
                Text(pace).font(.headline).monospacedDigit()
            }
        }.padding(10).background { WatchTileBackground(color: .blue, dimmed: dimmed) }
    }
    private var showsSpeed: Bool { ["Cycle", "Hand Cycling", "Downhill Skiing", "Snowboarding", "Skating"].contains(workout.activityName) }
    private var paceLabel: String {
        if showsSpeed { return "Avg km/h" }
        if workout.activityName == "Swimming" { return "Avg /100m" }
        if workout.activityName == "Rowing" { return "Avg /500m" }
        return "Avg /km"
    }
    private var pace: String {
        guard let meters = workout.distanceMeters, meters >= 50, workout.elapsed > 0 else { return "—" }
        if showsSpeed { return (meters / workout.elapsed * 3.6).formatted(.number.precision(.fractionLength(1))) }
        let unit: Double = workout.activityName == "Swimming" ? 100 : workout.activityName == "Rowing" ? 500 : 1000
        return Duration.seconds(workout.elapsed / (meters / unit)).formatted(.time(pattern: .minuteSecond))
    }
    private var zone: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Heart rate zone").font(.caption2)
                Spacer()
                Text(zoneValue.map { "Z\($0)" } ?? "—").font(.caption.bold()).foregroundStyle(accent)
            }
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { index in
                    Capsule().fill(zoneColor(index).opacity(zoneValue == index ? 1 : 0.22)).frame(height: 5)
                }
            }.accessibilityHidden(true)
            if workout.maxHeartRate == nil { Text("Add your birth date for estimated zones.").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.padding(10).background { WatchTileBackground(color: accent, dimmed: dimmed) }
            .accessibilityElement(children: .combine)
    }
    private var zoneValue: Int? {
        guard let max = workout.maxHeartRate, max > 0, let bpm = workout.freshHeartRate else { return nil }
        return min(5, Swift.max(0, Int((Double(bpm) / Double(max) - 0.4) * 10)))
    }
    private func zoneColor(_ zone: Int) -> Color { [.blue, .cyan, .green, .orange, .pink][zone - 1] }
    private var heartTrend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Heart rate", systemImage: "heart.fill").font(.caption).foregroundStyle(.pink)
            Text(workout.freshHeartRate.map { "\($0) BPM" } ?? "Waiting for a reading")
                .font(.title3.bold()).monospacedDigit()
            if workout.heartHistory.count >= 2 {
                GeometryReader { geometry in
                    let values = workout.heartHistory
                    let low = (values.min() ?? 0) - 5
                    let span = max(10, (values.max() ?? 0) - low + 5)
                    Path { path in
                        for (index, value) in values.enumerated() {
                            let point = CGPoint(x: geometry.size.width * Double(index) / Double(values.count - 1), y: geometry.size.height * (1 - (value - low) / span))
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }.stroke(.pink.gradient, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }.frame(height: 55).accessibilityHidden(true)
                Text("Recent readings").font(.caption2).foregroundStyle(.secondary)
            } else { Text("Your trend appears as readings arrive.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background { WatchTileBackground(color: .pink, dimmed: dimmed) }
    }
}

struct WatchTileBackground: View {
    let color: Color
    var dimmed = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(dimmed ? 0.08 : 0.32), Color(white: opaque ? 0.08 : 0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(dimmed ? 0.05 : 0.13), lineWidth: 0.7) }
    }
}

enum WatchPalette {
    static func color(for activity: ActivityType) -> Color {
        switch WatchWorkoutLayout.forActivity(activity) {
        case .court: return Color(red: 0.64, green: 0.95, blue: 0.28)
        case .distance: return .cyan
        case .strength: return .purple
        case .mindful: return .mint
        case .general: return .orange
        }
    }
}
