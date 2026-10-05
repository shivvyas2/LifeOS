import SwiftUI
import SwiftData
import SceneKit
import Charts
import AppSurfaces
import Persistence
import DesignSystem

struct BadmintonHistoryScreen: View {
    @Query(filter: #Predicate<WorkoutRecord> { $0.activityName == "Badminton" }, sort: \WorkoutRecord.start, order: .reverse)
    private var workouts: [WorkoutRecord]
    var body: some View {
        List {
            Section {
                Text("Your time on court").font(.title2.bold())
                Text("Apple Watch motion reviews arrive when your saved workout syncs. WHOOP and Apple Health sessions without motion data still show their workout totals.").font(.subheadline).foregroundStyle(.secondary)
            }
            if workouts.isEmpty {
                ContentUnavailableView("Your next session starts here", systemImage: "figure.badminton", description: Text("Enable experimental swing analysis in Your activity setup, then record badminton on your racket wrist."))
            }
            ForEach(workouts) { workout in
                NavigationLink {
                    BadmintonReviewScreen(workout: workout)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workout.start, format: .dateTime.month().day().hour().minute()).font(.headline)
                        Text(Self.subtitle(for: workout)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
        }.navigationTitle("Badminton").tint(LifeOSTokens.accent)
    }

    /// "32 min · Won 21-17 21-19 · with Priya", or the motion line when the
    /// session was not scored.
    static func subtitle(for workout: WorkoutRecord) -> String {
        var parts = ["\(workout.durationMinutes) min"]
        if let session = BadmintonReviewScreen.session(of: workout) {
            parts.append(session.summary)
            if let partner = session.teammate { parts.append("with \(partner)") }
        } else {
            parts.append(workout.swingAnalysisData == nil ? "Workout summary" : "Motion review")
        }
        return parts.joined(separator: " · ")
    }
}

struct BadmintonReviewScreen: View {
    let workout: WorkoutRecord
    /// Decoded once, here, rather than in a computed property: the body
    /// re-runs on every selection change, and decoding the whole review each
    /// time is work the screen does not need to repeat.
    ///
    /// Validated as well as decoded. The import path checks the same rules,
    /// but this screen reads whatever is stored, and every figure below is a
    /// conversion that traps on a value those rules exclude.
    private let analysis: SwingAnalysis?
    @State private var selected = 0
    private let jade = Color(red: 0.33, green: 0.91, blue: 0.72)
    init(workout: WorkoutRecord) {
        self.workout = workout
        // The record keeps whole minutes, so the next minute up bounds the
        // workout's real length.
        let elapsed = Double(workout.durationMinutes + 1) * 60
        analysis = workout.swingAnalysisData
            .flatMap { try? JSONDecoder().decode(SwingAnalysis.self, from: $0) }
            .flatMap { $0.isValid(elapsed: elapsed) ? $0 : nil }
    }
    private var event: SwingEvent? { analysis?.events.first(where: { $0.id == selected }) }
    /// Decoded and validated the same way as the motion review.
    static func session(of workout: WorkoutRecord) -> BadmintonSession? {
        workout.badmintonData
            .flatMap { try? JSONDecoder().decode(BadmintonSession.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("YOUR COURT REVIEW").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(jade)
                    Text("Every movement,\na little clearer.").font(.system(.largeTitle, weight: .semibold))
                    Text(workout.start, format: .dateTime.weekday().month().day()).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                HStack(spacing: 0) {
                    metric("Court time", "\(workout.durationMinutes)", "min")
                    metric("Energy", workout.energyKcal.map { String(Int($0.rounded())) } ?? "—", "kcal")
                    metric("Candidates", analysis.map { String($0.events.count) } ?? "—", "estimated")
                }.padding(.vertical, 18).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
                if let session = Self.session(of: workout) {
                    matchPanel(session)
                }
                if let analysis {
                    motionReview(analysis)
                } else {
                    panel("No wrist motion recorded", icon: "applewatch") {
                        Text("This session contains workout totals only. For your next badminton session, enable swing analysis and wear Apple Watch on your racket wrist. WHOOP does not expose swing motion through its public API.")
                    }
                }
                panel("What this session can tell you", icon: "scope") {
                    LabeledContent("Wrist rotation & acceleration", value: analysis == nil ? "Not recorded" : "Measured")
                    Divider().overlay(.white.opacity(0.1))
                    LabeledContent("Swing count", value: analysis == nil ? "Not recorded" : "Experimental estimate")
                    Divider().overlay(.white.opacity(0.1))
                    LabeledContent("Court position", value: "Not measured")
                    LabeledContent("Posture & impact angle", value: "Not measured")
                    LabeledContent("Shuttle / racket speed", value: "Not measured")
                }
                panel("A useful next session", icon: "sparkle") {
                    Text("Record a short drill and compare the candidates with a manual count. Practice swings and other quick arm movements can be included; gentle shots can be missed. Use video or a coach to review technique.")
                    if let events = analysis?.events, events.count > 1 {
                        let values = events.map(\.peakRotation).sorted()
                        Text("Median candidate peak: \(Int((values[values.count / 2] * 180 / .pi).rounded()))°/s at the wrist. A higher value does not mean a better shot.")
                    }
                }
            }.frame(maxWidth: 720).frame(maxWidth: .infinity).padding(22)
        }
        .background {
            LinearGradient(colors: [Color(red: 0.07, green: 0.28, blue: 0.24), Color(red: 0.025, green: 0.055, blue: 0.065), .black], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
        .foregroundStyle(.white).colorScheme(.dark)
        .navigationTitle("Badminton").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar).tint(jade)
    }
    private func motionReview(_ analysis: SwingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Motion replay").font(.title2.bold()); Spacer(); Text("EXPERIMENTAL").font(.caption2.bold()).foregroundStyle(jade) }
            Text("Recorded wrist orientation. Court and wrist position are illustrative; body posture and shot trajectory are not reconstructed.").font(.caption).foregroundStyle(.white.opacity(0.7))
            if analysis.events.isEmpty {
                ContentUnavailableView("No swing candidates", systemImage: "waveform.path", description: Text("No qualifying motion bursts were recorded. This does not mean you made no shots."))
            } else {
                // Keyed by the candidate, so choosing another one starts its
                // replay from the beginning, stopped.
                SwingReplay(event: event, tint: jade).id(selected)
                HStack {
                    Button { selected -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(selected == 0)
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Candidate \(selected + 1) of \(analysis.events.count)").font(.headline)
                        if let event { Text("\(Int(event.time) / 60):\(String(format: "%02d", Int(event.time) % 60)) active time").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { selected += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(selected + 1 >= analysis.events.count)
                }
                if let event {
                    HStack {
                        metric("Peak wrist rotation", String(Int((event.peakRotation * 180 / .pi).rounded())), "°/s")
                        metric("Peak acceleration", String(format: "%.1f", event.peakAcceleration), "g · gravity removed")
                    }
                }
                Chart(analysis.events) { event in
                    BarMark(x: .value("Active time", event.time / 60), y: .value("Peak wrist rotation", event.peakRotation * 180 / .pi), width: 3)
                        .foregroundStyle(event.id == selected ? .orange : jade.opacity(0.65))
                }.frame(height: 110).chartXAxisLabel("Active minutes").chartYAxisLabel("°/s")
                    .accessibilityLabel("Wrist rotation peaks for \(analysis.events.count) estimated swing candidates")
            }
            Text("Motion coverage: \(Int(analysis.sampledSeconds / 60))m \(Int(analysis.sampledSeconds) % 60)s sampled.\(analysis.interrupted ? " Sensor interruptions occurred." : "")\(analysis.truncated ? " Replay limit reached; later candidates were not retained." : "")")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
        }
    }
    private func matchPanel(_ session: BadmintonSession) -> some View {
        panel(session.kind == .match ? "Match" : "Practice", icon: "trophy") {
            if let score = session.score {
                Text(score.winner.map { $0 == .us ? "Won" : "Lost" } ?? "Unfinished")
                    .font(.system(.title, weight: .semibold)).foregroundStyle(.white)
                ForEach(Array((score.games + (score.current == BadmintonGame() ? [] : [score.current])).enumerated()), id: \.offset) { index, game in
                    LabeledContent("Game \(index + 1)", value: "\(game.us) – \(game.them)")
                    Divider().overlay(.white.opacity(0.1))
                }
            } else if let focus = session.focus {
                LabeledContent("Worked on", value: focus)
            }
            LabeledContent("Format", value: session.format == .doubles ? "Doubles" : "Singles")
            if let partner = session.teammate { LabeledContent("Partner", value: partner) }
            if !session.opponents.isEmpty { LabeledContent("Against", value: session.opponents.joined(separator: " & ")) }
        }
    }
    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.65))
            Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption2).foregroundStyle(jade)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
    }
    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(jade)
            content().font(.subheadline).foregroundStyle(.white.opacity(0.8))
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12)))
    }
}

/// The 3D replay and its controls, apart from the rest of the review.
///
/// Playback moves 25 times a second. Held by the review itself, every tick
/// re-ran the whole screen, the chart of every candidate included; held here,
/// a tick redraws the scene and the slider and nothing else.
private struct SwingReplay: View {
    let event: SwingEvent?
    let tint: Color
    @State private var playback = 0.0
    @State private var playing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var duration: Double { event?.duration ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WristCourtReplay(event: event, time: playback)
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("3D view of measured wrist orientation. Court position is not tracked.")
            HStack {
                Button { if playback >= duration { playback = 0 }; playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                }.buttonStyle(.glass).disabled(reduceMotion || event == nil)
                    .accessibilityLabel(playing ? "Pause replay" : "Play replay")
                Slider(value: $playback, in: 0...max(0.1, duration), onEditingChanged: { _ in playing = false })
                    .accessibilityLabel("Scrub recorded wrist orientation")
            }
            if reduceMotion { Text("Use the slider to inspect motion with Reduce Motion enabled.").font(.caption).foregroundStyle(.secondary) }
        }
        .tint(tint)
        .task(id: playing) {
            guard playing, !reduceMotion, duration > 0 else { playing = false; return }
            let start = Date.now.addingTimeInterval(-playback)
            while !Task.isCancelled && playing {
                playback = min(duration, Date.now.timeIntervalSince(start))
                if playback >= duration { playing = false; break }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
        .onDisappear { playing = false }
    }
}

/// A fixed display position deliberately avoids inventing a player track.
private struct WristCourtReplay: UIViewRepresentable {
    var event: SwingEvent?
    var time: Double
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(); let scene = SCNScene(); view.scene = scene
        view.backgroundColor = UIColor(red: 0.015, green: 0.075, blue: 0.07, alpha: 1)
        view.autoenablesDefaultLighting = true; view.allowsCameraControl = true
        // Framed on the wrist, which is the only thing that moves, with the
        // near half of the court and the net behind it for scale. From the
        // whole-court view this used to start at, the watch was a few pixels.
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(3.2, 3.8, 8.2)
        camera.look(at: SCNVector3(0, 1.4, 2.4)); scene.rootNode.addChildNode(camera)
        let floor = SCNBox(width: 6, height: 0.08, length: 12, chamferRadius: 0.06)
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.025, green: 0.32, blue: 0.25, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
        for x: Float in [-3, 3] { line(scene, x: x, z: 0, width: 0.04, length: 12) }
        for z: Float in [-6, -2, 0, 2, 6] { line(scene, x: 0, z: z, width: 6, length: 0.04) }
        line(scene, x: 0, z: -4, width: 0.04, length: 4); line(scene, x: 0, z: 4, width: 0.04, length: 4)
        let net = SCNBox(width: 6.1, height: 0.7, length: 0.025, chamferRadius: 0)
        net.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.18)
        let netNode = SCNNode(geometry: net); netNode.position = SCNVector3(0, 0.9, 0); scene.rootNode.addChildNode(netNode)
        let display = SCNNode(); display.position = SCNVector3(0, 2.3, 3.2); scene.rootNode.addChildNode(display)
        let wrist = SCNNode(); wrist.name = "wrist"; display.addChildNode(wrist)
        let arm = SCNCapsule(capRadius: 0.18, height: 1.8); arm.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        let armNode = SCNNode(geometry: arm); armNode.position.y = -0.6; wrist.addChildNode(armNode)
        let watch = SCNBox(width: 0.65, height: 0.48, length: 0.25, chamferRadius: 0.1)
        watch.firstMaterial?.diffuse.contents = UIColor.systemMint; watch.firstMaterial?.metalness.contents = 0.6
        wrist.addChildNode(SCNNode(geometry: watch))
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        guard let wrist = view.scene?.rootNode.childNode(withName: "wrist", recursively: true) else { return }
        guard let frames = event?.frames, let first = frames.first else { wrist.orientation = SCNQuaternion(0, 0, 0, 1); return }
        let frame = frames.last(where: { $0.t <= time }) ?? first
        // Relative attitude removes the arbitrary session reference direction.
        // Both ends are normalised first: the inverse of a quaternion that is
        // not unit length is not its conjugate, and a zero one has no inverse
        // at all, so an orientation built from either is NaN, which SceneKit
        // does not survive. Import checks rule both out; this does not rely on it.
        guard let start = Self.unit(first), let current = Self.unit(frame) else {
            wrist.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1); return
        }
        wrist.simdOrientation = start.inverse * current
    }
    private static func unit(_ frame: WristFrame) -> simd_quatf? {
        let q = simd_quatf(ix: Float(frame.x), iy: Float(frame.y), iz: Float(frame.z), r: Float(frame.w))
        let length = q.length
        guard length.isFinite, length > 0.5 else { return nil }
        return q.normalized
    }
    private func line(_ scene: SCNScene, x: Float, z: Float, width: CGFloat, length: CGFloat) {
        let box = SCNBox(width: width, height: 0.02, length: length, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.55)
        let node = SCNNode(geometry: box); node.position = SCNVector3(x, 0.06, z); scene.rootNode.addChildNode(node)
    }
}
