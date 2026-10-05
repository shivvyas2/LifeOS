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
    @State private var tags: BadmintonShotTags
    @Environment(\.modelContext) private var context
    /// The forehand sign learned from earlier sessions, used until this
    /// session's own tags say otherwise. Per account, like the draft.
    @AppStorage("badminton.strokeConvention", store: .currentAccount) private var savedConvention: Double = 0
    /// Ink, not a fixed green: the review follows the system appearance like
    /// the rest of the app instead of always being a dark screen of its own.
    @Environment(\.colorScheme) private var scheme
    private var jade: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    init(workout: WorkoutRecord) {
        self.workout = workout
        // The record keeps whole minutes, so the next minute up bounds the
        // workout's real length.
        let elapsed = Double(workout.durationMinutes + 1) * 60
        analysis = workout.swingAnalysisData
            .flatMap { try? JSONDecoder().decode(SwingAnalysis.self, from: $0) }
            .flatMap { $0.isValid(elapsed: elapsed) ? $0 : nil }
        _tags = State(initialValue: workout.shotTagsData
            .flatMap { try? JSONDecoder().decode(BadmintonShotTags.self, from: $0) } ?? BadmintonShotTags())
    }
    /// This session's tags when they settle it, otherwise the account's.
    private var convention: Double? {
        StrokeClassifier.convention(events: analysis?.events ?? [], tags: tags)
            ?? (savedConvention == 0 ? nil : savedConvention)
    }
    private func setTag(_ change: (inout BadmintonShotTag) -> Void) {
        var tag = tags[selected] ?? BadmintonShotTag()
        change(&tag)
        tags[selected] = tag
        workout.shotTagsData = try? JSONEncoder().encode(tags)
        try? context.save()
        if let learned = StrokeClassifier.convention(events: analysis?.events ?? [], tags: tags) { savedConvention = learned }
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
                    Text("YOUR COURT REVIEW").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(quiet)
                    Text("Every movement,\na little clearer.").font(.system(.largeTitle, weight: .semibold))
                    Text(workout.start, format: .dateTime.weekday().month().day()).font(.subheadline).foregroundStyle(quiet)
                }
                HStack(spacing: 0) {
                    metric("Court time", "\(workout.durationMinutes)", "min")
                    metric("Energy", workout.energyKcal.map { String(Int($0.rounded())) } ?? "—", "kcal")
                    metric("Candidates", analysis.map { String($0.events.count) } ?? "—", "estimated")
                }.padding(.vertical, 18).foregroundStyle(EditorialFieldTone.dusk.ink(scheme))
                .background(LinearGradient(colors: EditorialFieldTone.dusk.colors(scheme), startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                if let session = Self.session(of: workout) {
                    matchPanel(session)
                }
                if let analysis {
                    motionReview(analysis)
                    if !analysis.events.isEmpty { strokesPanel(analysis) }
                } else {
                    panel("No wrist motion recorded", icon: "applewatch") {
                        Text("This session contains workout totals only. For your next badminton session, enable swing analysis and wear Apple Watch on your racket wrist. WHOOP does not expose swing motion through its public API.")
                    }
                }
                panel("What this session can tell you", icon: "scope") {
                    LabeledContent("Wrist rotation & acceleration", value: analysis == nil ? "Not recorded" : "Measured")
                    Hairline()
                    LabeledContent("Swing count", value: analysis == nil ? "Not recorded" : "Experimental estimate")
                    Hairline()
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
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .foregroundStyle(jade)
        .navigationTitle("Badminton").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar).tint(jade)
    }
    private func motionReview(_ analysis: SwingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Motion replay").font(.title2.bold()); Spacer(); Text("EXPERIMENTAL").font(.caption2.bold()).foregroundStyle(jade) }
            Text("Recorded wrist orientation. Court and wrist position are illustrative; body posture and shot trajectory are not reconstructed.").font(.caption).foregroundStyle(quiet)
            if analysis.events.isEmpty {
                ContentUnavailableView("No swing candidates", systemImage: "waveform.path", description: Text("No qualifying motion bursts were recorded. This does not mean you made no shots."))
            } else {
                // Keyed by the candidate, so choosing another one starts its
                // replay from the beginning, stopped.
                SwingReplay(event: event, tint: jade, leftHanded: analysis.profile?.playingHand == .left).id(selected)
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
                    tagging(event)
                    HStack {
                        metric("Peak wrist rotation", String(Int((event.peakRotation * 180 / .pi).rounded())), "°/s")
                        metric("Peak acceleration", String(format: "%.1f", event.peakAcceleration), "g · gravity removed")
                    }
                }
                Chart(analysis.events) { event in
                    BarMark(x: .value("Active time", event.time / 60), y: .value("Peak wrist rotation", event.peakRotation * 180 / .pi), width: 3)
                        .foregroundStyle(event.id == selected ? LifeOSTokens.accent : jade.opacity(0.35))
                }.frame(height: 110).chartXAxisLabel("Active minutes").chartYAxisLabel("°/s")
                    .accessibilityLabel("Wrist rotation peaks for \(analysis.events.count) estimated swing candidates")
            }
            Text("Motion coverage: \(Int(analysis.sampledSeconds / 60))m \(Int(analysis.sampledSeconds) % 60)s sampled.\(analysis.interrupted ? " Sensor interruptions occurred." : "")\(analysis.truncated ? " Replay limit reached; later candidates were not retained." : "")")
                .font(.caption).foregroundStyle(quiet)
        }
    }
    /// What the player says about the selected candidate. A side that has
    /// not been tagged shows the call the learned convention makes, marked
    /// as such, so a wrong call is one tap from corrected.
    private func tagging(_ event: SwingEvent) -> some View {
        let tag = tags[event.id] ?? BadmintonShotTag()
        let called = StrokeClassifier.stroke(of: event, convention: convention, tags: BadmintonShotTags())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(BadmintonStroke.allCases, id: \.self) { stroke in
                    chip(stroke.title + (tag.stroke == nil && called == stroke ? " · auto" : ""),
                         on: tag.stroke == stroke || (tag.stroke == nil && called == stroke),
                         firm: tag.stroke == stroke) {
                        setTag { $0.stroke = $0.stroke == stroke ? nil : stroke; $0.notAShot = false }
                    }
                }
                Spacer(minLength: 0)
                chip("Not a shot", on: tag.notAShot, firm: true) {
                    setTag { $0.notAShot.toggle(); if $0.notAShot { $0.stroke = nil; $0.type = nil } }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(BadmintonShotType.allCases, id: \.self) { type in
                        chip(type.title, on: tag.type == type, firm: true) {
                            setTag { $0.type = $0.type == type ? nil : type; $0.notAShot = false }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
    private func chip(_ title: String, on: Bool, firm: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).frame(minHeight: 36)
                .foregroundStyle(on && firm ? LifeOSTokens.canvas.resolve(scheme) : jade)
                .background { if on && firm { Capsule().fill(jade) } }
                .overlay(Capsule().stroke(on ? jade : Editorial.rule(scheme), style: StrokeStyle(lineWidth: 1, dash: on && !firm ? [4, 3] : [])))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Forehand against backhand, from tags and the learned convention.
    private func strokesPanel(_ analysis: SwingAnalysis) -> some View {
        let summary = StrokeClassifier.summary(events: analysis.events, convention: convention, tags: tags)
        return panel("Your strokes", icon: "arrow.left.arrow.right") {
            if convention == nil {
                Text("Tag two or three swings as forehand or backhand in the replay above, and the rest of this session, and later ones, are called for you.")
            }
            LabeledContent("Forehand", value: sideLine(summary.forehand))
            Hairline()
            LabeledContent("Backhand", value: sideLine(summary.backhand))
            if summary.unclear > 0 {
                Hairline()
                LabeledContent("Too close to call", value: "\(summary.unclear)")
            }
            if let stronger = summary.stronger {
                Text("Your \(stronger.title.lowercased()) moves the wrist faster on average. Wrist speed is not shot quality; use it to see which side you commit to.")
                    .font(.caption).foregroundStyle(quiet)
            }
            if !summary.types.isEmpty {
                Text(BadmintonShotType.allCases.compactMap { type in summary.types[type].map { "\($0) \(type.title.lowercased())" } }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(jade)
            }
        }
    }
    private func sideLine(_ side: StrokeClassifier.Side) -> String {
        guard side.count > 0, let peak = side.averagePeak else { return "None yet" }
        return "\(side.count) · avg \(Int((peak * 180 / .pi).rounded()))°/s"
    }

    private func matchPanel(_ session: BadmintonSession) -> some View {
        panel(session.kind == .match ? "Match" : "Practice", icon: "trophy") {
            if let score = session.score {
                Text(score.winner.map { $0 == .us ? "Won" : "Lost" } ?? "Unfinished")
                    .font(Editorial.headline(28)).foregroundStyle(jade)
                ForEach(Array((score.games + (score.current == BadmintonGame() ? [] : [score.current])).enumerated()), id: \.offset) { index, game in
                    LabeledContent("Game \(index + 1)", value: "\(game.us) – \(game.them)")
                    Hairline()
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
            Text(title).font(.caption).foregroundStyle(quiet)
            Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption2).foregroundStyle(jade)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
    }
    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(jade)
            content().font(.subheadline).foregroundStyle(quiet)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Editorial.rule(scheme)))
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
    var leftHanded = false
    @State private var playback = 0.0
    @State private var playing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var duration: Double { event?.duration ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WristCourtReplay(event: event, time: playback, leftHanded: leftHanded)
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("3D player figure whose racket arm follows the measured wrist orientation. Court position and posture are not tracked.")
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
    /// Mirrors the figure, so a left-hander sees the racket in the left hand.
    var leftHanded = false
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(); let scene = SCNScene(); view.scene = scene
        view.backgroundColor = UIColor(red: 0.015, green: 0.075, blue: 0.07, alpha: 1)
        view.autoenablesDefaultLighting = true; view.allowsCameraControl = true
        // Framed on the player, whose racket arm is the only thing that
        // moves, with the net behind for scale. From the whole-court view
        // this used to start at, the figure was a few pixels.
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(2.1, 2.05, 6.5)
        camera.look(at: SCNVector3(0, 1.15, 3.0)); scene.rootNode.addChildNode(camera)
        // A regulation court in metres (BWF Laws, Appendix 1): 13.4 by 6.1
        // for doubles, singles sidelines 0.46 inside, short service lines
        // 1.98 from the net, doubles long service lines 0.76 inside the back
        // line, centre lines from the short service line back.
        let floor = SCNBox(width: 6.5, height: 0.06, length: 13.8, chamferRadius: 0.04)
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.025, green: 0.32, blue: 0.25, alpha: 1)
        let floorNode = SCNNode(geometry: floor); floorNode.position.y = -0.03
        scene.rootNode.addChildNode(floorNode)
        let halfWidth: Float = 3.05, singles: Float = 2.59, back: Float = 6.7
        for x in [-halfWidth, halfWidth, -singles, singles] { line(scene, x: x, z: 0, width: 0.04, length: CGFloat(back * 2)) }
        for z in [-back, back, -5.94, 5.94, -1.98, 1.98] { line(scene, x: 0, z: z, width: CGFloat(halfWidth * 2), length: 0.04) }
        let centreLength: Float = back - 1.98
        line(scene, x: 0, z: 1.98 + centreLength / 2, width: 0.04, length: CGFloat(centreLength))
        line(scene, x: 0, z: -(1.98 + centreLength / 2), width: 0.04, length: CGFloat(centreLength))
        // The net: 1.55 m at the posts, a 0.76 m deep mesh band below the top.
        let net = SCNBox(width: CGFloat(halfWidth * 2), height: 0.76, length: 0.02, chamferRadius: 0)
        net.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.18)
        let netNode = SCNNode(geometry: net); netNode.position = SCNVector3(0, 1.55 - 0.38, 0); scene.rootNode.addChildNode(netNode)
        let tape = SCNBox(width: CGFloat(halfWidth * 2), height: 0.04, length: 0.03, chamferRadius: 0)
        tape.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.85)
        let tapeNode = SCNNode(geometry: tape); tapeNode.position = SCNVector3(0, 1.55, 0); scene.rootNode.addChildNode(tapeNode)
        for x in [-halfWidth, halfWidth] {
            let post = SCNCylinder(radius: 0.03, height: 1.55)
            post.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.7)
            let postNode = SCNNode(geometry: post); postNode.position = SCNVector3(x, 0.775, 0); scene.rootNode.addChildNode(postNode)
        }
        scene.rootNode.addChildNode(Self.player(leftHanded: leftHanded))
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
    // MARK: - The player

    /// A brutalist stick figure in the ready position on the near half: flat
    /// concrete blocks for limbs, a box head with a glowing visor, a glowing
    /// seam down the torso and a glowing racket frame.
    ///
    /// Only the forearm, hand and racket move. They hang from a pivot at the
    /// elbow named "wrist", which `updateUIView` turns by the recorded wrist
    /// orientation: the watch sits on the forearm, so its attitude is the
    /// forearm's. The body is fixed on purpose, because posture is not
    /// measured and the screen says so; animating it would invent a pose.
    static func player(leftHanded: Bool) -> SCNNode {
        let concrete = material(UIColor(white: 0.9, alpha: 1))
        let shadowed = material(UIColor(white: 0.72, alpha: 1))
        let glow = material(UIColor(red: 0.94, green: 0.34, blue: 0.18, alpha: 1), glows: true)
        let root = SCNNode()
        root.position = SCNVector3(0, 0, 3.4)
        // Facing the net, which is towards -z.
        if leftHanded { root.scale.x = -1 }

        // Ground the figure with a soft footprint.
        let footprint = SCNCylinder(radius: 0.42, height: 0.004)
        footprint.firstMaterial = material(UIColor(white: 0, alpha: 0.35))
        let print = SCNNode(geometry: footprint); print.position.y = 0.012; root.addChildNode(print)

        // Legs in a split ready stance, knees soft.
        root.addChildNode(segment(from: [-0.17, 0.0, 0.10], to: [-0.13, 0.48, 0.02], thickness: 0.1, material: shadowed))
        root.addChildNode(segment(from: [-0.13, 0.48, 0.02], to: [-0.11, 0.95, 0.0], thickness: 0.11, material: concrete))
        root.addChildNode(segment(from: [0.19, 0.0, -0.14], to: [0.15, 0.48, -0.05], thickness: 0.1, material: shadowed))
        root.addChildNode(segment(from: [0.15, 0.48, -0.05], to: [0.11, 0.95, 0.0], thickness: 0.11, material: concrete))
        // Pelvis, torso and the glowing seam.
        root.addChildNode(box(0.34, 0.12, 0.18, at: [0, 0.98, 0], concrete))
        let torso = box(0.36, 0.56, 0.18, at: [0, 1.32, -0.02], concrete)
        torso.eulerAngles.x = 0.12
        torso.addChildNode(box(0.025, 0.5, 0.01, at: [0, 0, -0.096], glow))
        root.addChildNode(torso)
        // Neck, head and visor.
        root.addChildNode(box(0.08, 0.08, 0.08, at: [0, 1.64, -0.04], shadowed))
        let head = box(0.22, 0.24, 0.22, at: [0, 1.79, -0.05], concrete)
        head.addChildNode(box(0.19, 0.035, 0.012, at: [0, 0.02, -0.112], glow))
        root.addChildNode(head)

        // The free arm, bent and held up for balance.
        let freeShoulder: SIMD3<Float> = [-0.22, 1.52, -0.02]
        let freeElbow: SIMD3<Float> = [-0.36, 1.3, -0.18]
        root.addChildNode(segment(from: freeShoulder, to: freeElbow, thickness: 0.08, material: concrete))
        root.addChildNode(segment(from: freeElbow, to: [-0.3, 1.5, -0.36], thickness: 0.07, material: shadowed))

        // The racket arm. The upper arm is fixed; everything from the elbow
        // out hangs from the "wrist" pivot.
        let shoulder: SIMD3<Float> = [0.22, 1.52, -0.02]
        let elbow: SIMD3<Float> = [0.4, 1.32, -0.2]
        root.addChildNode(segment(from: shoulder, to: elbow, thickness: 0.08, material: concrete))
        let pivot = SCNNode(); pivot.name = "wrist"; pivot.simdPosition = elbow
        root.addChildNode(pivot)
        let hand: SIMD3<Float> = [0.02, 0.27, -0.12]
        pivot.addChildNode(segment(from: [0, 0, 0], to: hand, thickness: 0.07, material: concrete))
        pivot.addChildNode(box(0.07, 0.09, 0.07, at: hand + [0, 0.04, -0.01], shadowed))
        // Racket: handle, shaft, and the glowing frame with faint strings.
        let shaftEnd = hand + [0.0, 0.42, -0.16]
        pivot.addChildNode(segment(from: hand, to: shaftEnd, thickness: 0.022, material: shadowed))
        let headCentre = shaftEnd + [0, 0.14, -0.05]
        let frame = SCNTorus(ringRadius: 0.11, pipeRadius: 0.009)
        frame.firstMaterial = glow
        let frameNode = SCNNode(geometry: frame)
        frameNode.simdPosition = headCentre
        frameNode.simdOrientation = simd_quatf(from: [0, 1, 0], to: simd_normalize([0, 0.3, 0.95]))
        frameNode.scale = SCNVector3(1, 1, 1.3)
        let strings = SCNCylinder(radius: 0.105, height: 0.002)
        strings.firstMaterial = material(UIColor(white: 1, alpha: 0.18))
        frameNode.addChildNode(SCNNode(geometry: strings))
        pivot.addChildNode(frameNode)
        return root
    }

    private static func material(_ color: UIColor, glows: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = glows ? .constant : .lambert
        if glows { material.emission.contents = color }
        if color.cgColor.alpha < 1 { material.transparency = color.cgColor.alpha; material.blendMode = .alpha }
        return material
    }

    private static func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, at position: SIMD3<Float>, _ material: SCNMaterial) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: min(width, length) * 0.12)
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry); node.simdPosition = position
        return node
    }

    /// A square-section limb from one joint to the next.
    private static func segment(from a: SIMD3<Float>, to b: SIMD3<Float>, thickness: CGFloat, material: SCNMaterial) -> SCNNode {
        let length = simd_length(b - a)
        let node = box(thickness, CGFloat(length), thickness, at: (a + b) / 2, material)
        node.simdOrientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(b - a))
        return node
    }

    private func line(_ scene: SCNScene, x: Float, z: Float, width: CGFloat, length: CGFloat) {
        let box = SCNBox(width: width, height: 0.02, length: length, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.55)
        let node = SCNNode(geometry: box); node.position = SCNVector3(x, 0.011, z); scene.rootNode.addChildNode(node)
    }
}
