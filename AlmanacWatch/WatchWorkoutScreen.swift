import SwiftUI
import AppSurfaces

/// Metrics and controls occupy separate crown-scrollable pages, so a small
/// Watch never has to squeeze a pause target between live readings.
struct WatchWorkoutScreen: View {
    let workout: WatchWorkoutController
    @State private var page = 0
    @State private var confirmingEnd = false
    @Environment(\.isLuminanceReduced) private var dimmed
    private var theme: WatchActivityTheme { WatchPalette.theme(for: workout.activity ?? ActivityCatalog.other) }
    private var accent: Color { theme.highlight }

    var body: some View {
        TimelineView(.periodic(from: .now, by: dimmed ? 60 : 5)) { _ in
        TabView(selection: $page) {
            ScrollView {
                VStack(spacing: 8) {
                    hero
                    HStack(spacing: 0) {
                        metric("Heart rate", value: workout.freshHeartRate.map(String.init) ?? "—", unit: "BPM", icon: "heart.fill")
                        Rectangle().fill(accent.opacity(0.18)).frame(width: 0.5, height: 42).accessibilityHidden(true)
                        metric("Energy", value: workout.energyKcal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", unit: "kcal", icon: "flame.fill")
                    }
                    .background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
                    if workout.activityName == "Badminton" { swings }
                    if workout.layout == .strength { strength }
                    else if workout.layout == .distance { distance }
                    else if workout.activity?.showsZones == true { zone }
                    Text(workout.mirroringFailed ? "Recording on Watch · sync later" : "Live with iPhone")
                        .font(.system(size: 10)).foregroundStyle(accent.opacity(0.85))
                    Button { page = 2 } label: { Label("Controls", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.glass).tint(accent.opacity(0.15))
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
                VStack(spacing: 8) {
                    VStack(spacing: 3) {
                        Text(workout.state == .paused ? "Workout paused" : "Active time")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        timer.font(.system(size: 28, weight: .semibold, design: .rounded))
                    }.frame(maxWidth: .infinity).padding(8)
                        .background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
                    if let error = workout.lastError {
                        Text(error).font(.caption2).foregroundStyle(.orange)
                    }
                    if workout.state == .ending {
                        if workout.lastError != nil { Button("Retry save") { workout.retrySave() }.buttonStyle(.glassProminent).tint(.orange) }
                        else { ProgressView("Saving workout") }
                    } else {
                        Button { workout.state == .paused ? workout.resume() : workout.pause() } label: {
                            Label(workout.state == .paused ? "Resume" : "Pause", systemImage: workout.state == .paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }.buttonStyle(.glassProminent).tint(.orange)
                        Button { confirmingEnd = true } label: {
                            Label("Finish & save", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 24)
                        }.buttonStyle(.glass).tint(accent.opacity(0.15))
                        if workout.isStrength { repControls }
                    }
                    Label("Saves to Apple Health", systemImage: "applewatch")
                        .font(.caption2).foregroundStyle(accent.opacity(0.85))
                }.padding(.horizontal, 4)
            }.tag(2)
        }
        .tabViewStyle(.page)
        .containerBackground(for: .navigation) { WatchActivityBackdrop(theme: theme) }
        .tint(accent)
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
                HStack(spacing: 5) {
                    activitySymbol(workout.activity?.symbol ?? "figure.run").font(.system(size: 14))
                    Text("Active time").font(.system(size: 10, weight: .medium))
                }
                Spacer(minLength: 4)
                Text(workout.state == .paused ? "Paused" : heroLabel).font(.system(size: 9, weight: .semibold)).textCase(.uppercase).tracking(1)
            }.foregroundStyle(accent)
            timer.font(.system(size: 36, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.65).lineLimit(1)
            if workout.layout == .court { court.frame(height: 14).accessibilityHidden(true) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed, emphasized: true) }
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
    private func metric(_ title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .medium)).foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.72))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(value) \(unit)")
    }
    private var swings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.swingAnalysis.map { "\($0.events.count) swing candidates" } ?? "Swing analysis off").font(.headline)
            if let peak = workout.swingAnalysis?.peakRotation {
                Text("Peak wrist \(Int((peak * 180 / .pi).rounded()))°/s").font(.caption2).foregroundStyle(accent)
            }
            Text(workout.swingAnalysis == nil ? "Enable in Your movement setup" : workout.motionStatus).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
    }
    private var strength: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(workout.reps.map(String.init) ?? "—") reps").font(.title3.bold()).monospacedDigit()
                Text("Wrist estimate · adjust in Controls").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text("SET\n\(workout.setIndex ?? 1)").font(.caption2.bold()).multilineTextAlignment(.center).foregroundStyle(accent)
        }.padding(10).background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
    }
    private var repControls: some View {
        VStack(spacing: 8) {
            Text("\(workout.reps.map(String.init) ?? "—") reps · set \(workout.setIndex ?? 1)").font(.headline)
            HStack {
                Button("−1") { workout.removeRep() }.accessibilityLabel("Remove one rep")
                Button("+1") { workout.addRep() }.accessibilityLabel("Add one rep")
            }.buttonStyle(.glass).tint(accent.opacity(0.15))
            Button("Next set") { workout.nextSet() }.buttonStyle(.glass).tint(accent.opacity(0.15))
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
        }.padding(10).background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
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
                    Capsule().fill(zoneValue == index ? accent : accent.opacity(0.18)).frame(height: 5)
                }
            }.accessibilityHidden(true)
            if workout.maxHeartRate == nil { Text("Add your birth date for estimated zones.").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.padding(10).background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
            .accessibilityElement(children: .combine)
    }
    private var zoneValue: Int? {
        guard let max = workout.maxHeartRate, max > 0, let bpm = workout.freshHeartRate else { return nil }
        return min(5, Swift.max(0, Int((Double(bpm) / Double(max) - 0.4) * 10)))
    }
    private var heartTrend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Heart rate", systemImage: "heart.fill").font(.caption).foregroundStyle(accent)
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
                    }.stroke(accent.gradient, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }.frame(height: 42).accessibilityHidden(true)
                Text("Recent readings").font(.caption2).foregroundStyle(.secondary)
            } else { Text("Your trend appears as readings arrive.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background { WatchTileBackground(color: theme.tint, companion: theme.glow, dimmed: dimmed) }
    }
}

/// Static gradients give the glass depth without running an animation or
/// blur pass continuously during a workout.
struct WatchTileBackground: View {
    let color: Color
    var companion: Color? = nil
    var dimmed = false
    var emphasized = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isLuminanceReduced) private var alwaysOn
    private var reduced: Bool { dimmed || alwaysOn }

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            let radius = max(proxy.size.width, proxy.size.height)
            ZStack {
                // A dark optical base keeps white numerals readable over the
                // lighter edge of the screen's ambient gradient.
                shape.fill(Color(white: 0.025).opacity(opaque || reduced ? 1 : emphasized ? 0.58 : 0.48))
                if !reduced {
                    shape.fill(RadialGradient(colors: [color.opacity(emphasized ? 0.32 : 0.18), .clear],
                        center: .bottomTrailing, startRadius: 0, endRadius: radius * 1.05))
                    shape.fill(RadialGradient(colors: [(companion ?? color).opacity(emphasized ? 0.16 : 0.08), .clear],
                        center: .bottomLeading, startRadius: 0, endRadius: radius * 0.78))
                    if !opaque {
                        shape.fill(LinearGradient(stops: [
                            .init(color: .white.opacity(emphasized ? 0.14 : 0.08), location: 0),
                            .init(color: .white.opacity(0.035), location: 0.35),
                            .init(color: .clear, location: 0.65)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                shape.strokeBorder(LinearGradient(colors: [
                    .white.opacity(reduced ? 0.10 : contrast == .increased ? 0.7 : emphasized ? 0.34 : 0.23),
                    .white.opacity(0.06),
                    (companion ?? color).opacity(reduced ? 0.10 : 0.22),
                    .white.opacity(reduced ? 0.08 : 0.12)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: contrast == .increased ? 1.2 : 0.8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WatchActivityTheme {
    let tint: Color
    let glow: Color
    let highlight: Color
}

/// A shaded activity color flows across the crown area into a pale reflected edge,
/// echoing the supplied gradient without placing white text on a white base.
struct WatchActivityBackdrop: View {
    let theme: WatchActivityTheme
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if !dimmed && !opaque {
                    LinearGradient(stops: [
                        .init(color: theme.tint.opacity(0.48), location: 0),
                        .init(color: theme.tint.opacity(0.36), location: 0.40),
                        .init(color: theme.tint.opacity(0.55), location: 0.82),
                        .init(color: theme.glow.opacity(0.48), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [theme.glow.opacity(0.42), .clear],
                        center: UnitPoint(x: 1.1, y: 0.84), startRadius: 0, endRadius: proxy.size.width * 0.9)
                    RadialGradient(colors: [.white.opacity(0.21), .clear],
                        center: UnitPoint(x: -0.2, y: 1.2), startRadius: 0, endRadius: proxy.size.width * 0.9)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

enum WatchPalette {
    static func color(for activity: ActivityType) -> Color { theme(for: activity).highlight }
    static func theme(for activity: ActivityType) -> WatchActivityTheme {
        switch activity.name {
        case "Badminton", "Tennis", "Table Tennis", "Pickleball", "Squash", "Racquetball":
            return .init(tint: Color(red: 0.10, green: 0.58, blue: 0.34), glow: Color(red: 0.72, green: 0.88, blue: 0.24), highlight: Color(red: 0.79, green: 1, blue: 0.55))
        case "Run", "Wheelchair Run Pace":
            return .init(tint: Color(red: 0.08, green: 0.24, blue: 0.95), glow: Color(red: 0.35, green: 0.71, blue: 1), highlight: Color(red: 0.68, green: 0.86, blue: 1))
        case "Walk", "Hiking", "Wheelchair Walk Pace":
            return .init(tint: Color(red: 0.03, green: 0.49, blue: 0.48), glow: Color(red: 0.36, green: 0.89, blue: 0.68), highlight: Color(red: 0.60, green: 1, blue: 0.82))
        case "Cycle", "Hand Cycling":
            return .init(tint: Color(red: 0.75, green: 0.29, blue: 0.07), glow: Color(red: 1, green: 0.65, blue: 0.27), highlight: Color(red: 1, green: 0.83, blue: 0.56))
        default: break
        }
        switch activity.group {
        case .strength:
            return .init(tint: Color(red: 0.42, green: 0.16, blue: 0.85), glow: Color(red: 0.85, green: 0.36, blue: 0.81), highlight: Color(red: 0.88, green: 0.74, blue: 1))
        case .mindAndBody:
            return .init(tint: Color(red: 0.03, green: 0.47, blue: 0.38), glow: Color(red: 0.47, green: 0.79, blue: 0.70), highlight: Color(red: 0.70, green: 1, blue: 0.87))
        case .water:
            return .init(tint: Color(red: 0.02, green: 0.35, blue: 0.80), glow: Color(red: 0.13, green: 0.85, blue: 0.85), highlight: Color(red: 0.60, green: 0.95, blue: 1))
        case .outdoor:
            return .init(tint: Color(red: 0.21, green: 0.33, blue: 0.67), glow: Color(red: 0.57, green: 0.76, blue: 0.96), highlight: Color(red: 0.80, green: 0.90, blue: 1))
        case .danceAndPlay:
            return .init(tint: Color(red: 0.68, green: 0.14, blue: 0.44), glow: Color(red: 0.99, green: 0.44, blue: 0.61), highlight: Color(red: 1, green: 0.74, blue: 0.83))
        default:
            return .init(tint: Color(red: 0.75, green: 0.22, blue: 0.10), glow: Color(red: 1, green: 0.60, blue: 0.28), highlight: Color(red: 1, green: 0.79, blue: 0.60))
        }
    }
}
