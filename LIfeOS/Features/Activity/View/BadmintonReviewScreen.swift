import SwiftUI
import SwiftData
import SceneKit
import Charts
import AppSurfaces
import Persistence
import DesignSystem

/// Every past badminton session, the ones with a motion review first, and
/// for the rest the reason there is none. Opens any of them in the review.
struct BadmintonHistoryScreen: View {
    /// Starts the demo from the empty state, where there is a recorder to
    /// start it on: Begin activity passes it; the Health hub does not.
    var onDemo: (() -> Void)? = nil
    @Query(filter: #Predicate<WorkoutRecord> { $0.activityName == "Badminton" }, sort: \WorkoutRecord.start, order: .reverse)
    private var workouts: [WorkoutRecord]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var reviewed: [WorkoutRecord] { workouts.filter { BadmintonReviewScreen.motionState(of: $0) == .readable } }
    private var summaries: [WorkoutRecord] { workouts.filter { BadmintonReviewScreen.motionState(of: $0) != .readable } }
    private static let emptySentence = "Every badminton session lands here with its score, and with the swing replay once your Watch has synced it."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorialMasthead(eyebrow: "Badminton", title: "Past sessions",
                                  detail: "Scores arrive with the session. Motion reviews arrive when your Watch syncs, and only from a Watch worn on your racket wrist.")
                if workouts.isEmpty {
                    if let onDemo {
                        EditorialEmptyState(sentence: Self.emptySentence, action: "Try the demo", onAction: { dismiss(); onDemo() }) { sampleRow }
                    } else {
                        EditorialEmptyState(sentence: Self.emptySentence) { sampleRow }
                    }
                } else {
                    if !reviewed.isEmpty { section(index: 1, title: "Motion reviews", rows: reviewed) }
                    if !summaries.isEmpty { section(index: reviewed.isEmpty ? 1 : 2, title: "Summaries only", rows: summaries) }
                }
            }.frame(maxWidth: 720).frame(maxWidth: .infinity).padding(22)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("Badminton").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(LifeOSTokens.primaryText.resolve(scheme))
    }

    private func section(index: Int, title: String, rows: [WorkoutRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSectionHeader(index: index, title: title)
            ForEach(rows) { workout in
                NavigationLink { BadmintonReviewScreen(workout: workout) } label: {
                    row(date: workout.start, line: Self.subtitle(for: workout), reason: Self.reason(for: workout))
                }
                .buttonStyle(.plain)
            }
        }
    }
    /// What a row will look like, for the empty state's ghost.
    private var sampleRow: some View {
        row(date: .now.addingTimeInterval(-2 * 86400), line: "38 min · Won 21-17 18-21 21-15 · with Priya", reason: nil)
    }
    private func row(date: Date, line: String, reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date, format: .dateTime.weekday(.abbreviated).month().day().hour().minute()).font(LifeOSType.rowTitle)
                    Text(line).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                    if let reason {
                        Text(reason).font(LifeOSType.caption).foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(Editorial.quietInk(scheme)).accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            Hairline()
        }
        .contentShape(.rect)
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
    }
    /// Why a row has no motion review, or nil when it has one.
    static func reason(for workout: WorkoutRecord) -> String? {
        BadmintonSessionStatus.reason(externalID: workout.externalID, start: workout.start,
                                      motion: BadmintonReviewScreen.motionState(of: workout))
    }

    /// "32 min · Won 21-17 21-19 · with Priya", or the motion line when the
    /// session was not scored.
    static func subtitle(for workout: WorkoutRecord) -> String {
        var parts = ["\(workout.durationMinutes) min"]
        if let session = BadmintonReviewScreen.session(of: workout) {
            parts.append(session.summary)
            if let partner = session.teammate { parts.append("with \(partner)") }
        } else {
            parts.append(BadmintonReviewScreen.motionState(of: workout) == .readable ? "Motion review" : "Workout summary")
        }
        return parts.joined(separator: " · ")
    }
}

/// The session just finished, by the id the recorder wrote it under, or the
/// list when no row answers to it.
struct BadmintonLatestReview: View {
    @Query private var workouts: [WorkoutRecord]
    init(externalID: String?) {
        let id = externalID ?? ""
        _workouts = Query(filter: #Predicate<WorkoutRecord> { $0.externalID == id })
    }
    var body: some View {
        if let workout = workouts.first { BadmintonReviewScreen(workout: workout) } else { BadmintonHistoryScreen() }
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
    @State private var showInfo = false
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
    /// A demo's review is a record that was never stored; the screen says so.
    private var isDemo: Bool { workout.externalID.hasPrefix("almanac-demo:") }
    /// Whether the stored motion, if any, passes the same validation this
    /// screen applies before showing it. The history list groups by this.
    static func motionState(of workout: WorkoutRecord) -> BadmintonMotionState {
        guard let data = workout.swingAnalysisData else { return .none }
        let elapsed = Double(workout.durationMinutes + 1) * 60
        let analysis = try? JSONDecoder().decode(SwingAnalysis.self, from: data)
        return analysis?.isValid(elapsed: elapsed) == true ? .readable : .unreadable
    }
    /// Decoded and validated the same way as the motion review.
    static func session(of workout: WorkoutRecord) -> BadmintonSession? {
        workout.badmintonData
            .flatMap { try? JSONDecoder().decode(BadmintonSession.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    EditorialMasthead(eyebrow: isDemo ? "Badminton · Demo" : "Badminton · \(workout.start.formatted(.dateTime.weekday().month().day()))",
                                      title: "Court review")
                    Button { showInfo = true } label: { Image(systemName: "info.circle").font(.title3) }
                        .buttonStyle(.plain).frame(width: 44, height: 44)
                        .accessibilityLabel("About this data")
                }
                HStack(spacing: 0) {
                    metric("Court time", "\(workout.durationMinutes)", "min", onInk: solid)
                    metric("Energy", workout.energyKcal.map { String(Int($0.rounded())) } ?? "—", "kcal", onInk: solid)
                    metric("Swings", analysis.map { String($0.events.count) } ?? "—", "estimated", onInk: solid)
                }.padding(.vertical, 18).foregroundStyle(solid ? .white : EditorialFieldTone.dusk.ink(scheme))
                .background {
                    // Solid ink in light mode, the session's numbers set like
                    // a scoreboard; the dusk field in dark mode.
                    if solid {
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(LifeOSTokens.primaryText.resolve(.light))
                    } else {
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .fill(LinearGradient(colors: EditorialFieldTone.dusk.colors(scheme), startPoint: .top, endPoint: .bottom))
                    }
                }
                if isDemo {
                    Text("A demo session, scripted on this iPhone. Nothing here was saved.")
                        .font(LifeOSType.caption).foregroundStyle(quiet)
                }
                if let session = Self.session(of: workout) {
                    matchPanel(session)
                }
                if let analysis {
                    motionReview(analysis)
                    if !analysis.events.isEmpty { strokesPanel(analysis) }
                } else {
                    panel("No wrist data", icon: "applewatch") {
                        if let reason = BadmintonHistoryScreen.reason(for: workout) { Text(reason) }
                        Text("For the motion review, turn on swing analysis in Your activity setup and wear your Watch on your racket wrist.")
                    }
                }
            }.frame(maxWidth: 720).frame(maxWidth: .infinity).padding(22)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .foregroundStyle(jade)
        .navigationTitle("Badminton").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar).tint(jade)
        .sheet(isPresented: $showInfo) { infoSheet.presentationDetents([.medium, .large]) }
    }

    /// Everything the screen used to say in paragraphs, kept for whoever
    /// wants it and out of the way of everyone else.
    private var infoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialSectionHeader(index: 1, title: "Measured")
                    EditorialRow("Wrist rotation and acceleration", value: analysis == nil ? "Not recorded" : "Yes")
                    EditorialRow("Swings", value: analysis == nil ? "Not recorded" : "Estimated")
                    if let analysis {
                        EditorialRow("Motion sampled", value: "\(Int(analysis.sampledSeconds / 60))m \(Int(analysis.sampledSeconds) % 60)s")
                        if analysis.interrupted { EditorialRow("Sensor gaps", value: "Some") }
                        if analysis.truncated { EditorialRow("Replay limit", value: "Reached") }
                    }
                    EditorialSectionHeader(index: 2, title: "Not measured").padding(.top, Space.x3)
                    EditorialRow("Court position", value: "No")
                    EditorialRow("Posture", value: "No")
                    EditorialRow("Shuttle and racket speed", value: "No")
                    EditorialSectionHeader(index: 3, title: "How to read it").padding(.top, Space.x3)
                    Text("The figure plays the shot you tagged, or the side and serve the app estimated. Its body is an illustration; only the wrist is recorded. Wrist speed shows commitment, not shot quality. Practice swings can be counted, and gentle shots missed.")
                        .font(LifeOSType.secondary).foregroundStyle(quiet).padding(.top, Space.x1)
                }
                .padding(22)
            }
            .navigationTitle("About this data").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
        }
    }
    private func motionReview(_ analysis: SwingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            EditorialSectionHeader(index: 1, title: "Replay") { EditorialTag("Beta") }
            if analysis.events.isEmpty {
                ContentUnavailableView("No swings found", systemImage: "waveform.path")
            } else {
                // Keyed by the candidate, so choosing another one starts its
                // replay from the beginning, stopped.
                SwingReplay(event: event, tint: jade, leftHanded: analysis.profile?.playingHand == .left,
                            motion: event.flatMap { SwingMotion.choose(for: $0, in: analysis.events, tags: tags, convention: convention) })
                    .id(selected)
                HStack {
                    Button { selected -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(selected == 0)
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Swing \(selected + 1) of \(analysis.events.count)").font(.headline)
                        if let event {
                            Text("\(Int(event.time) / 60):\(String(format: "%02d", Int(event.time) % 60)) · \(replayLine(event, analysis))")
                                .font(.caption).foregroundStyle(quiet)
                        }
                    }
                    Spacer()
                    Button { selected += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(selected + 1 >= analysis.events.count)
                }
                if let event {
                    tagging(event)
                    HStack {
                        metric("Wrist speed", String(Int((event.peakRotation * 180 / .pi).rounded())), "°/s")
                        metric("Acceleration", String(format: "%.1f", event.peakAcceleration), "g")
                    }
                }
                Chart(analysis.events) { event in
                    BarMark(x: .value("Active time", event.time / 60), y: .value("Peak wrist rotation", event.peakRotation * 180 / .pi), width: 3)
                        .foregroundStyle(event.id == selected ? LifeOSTokens.accent : jade.opacity(0.35))
                }.frame(height: 90).chartXAxisLabel("Minutes").chartYAxis(.hidden)
                    .accessibilityLabel("Wrist rotation peaks for \(analysis.events.count) estimated swing candidates")
            }
        }
    }
    /// What the replay is showing, in a few words.
    private func replayLine(_ event: SwingEvent, _ analysis: SwingAnalysis) -> String {
        guard let motion = SwingMotion.choose(for: event, in: analysis.events, tags: tags, convention: convention) else { return "wrist only" }
        let tagged = tags[event.id]?.type != nil || tags[event.id]?.notAShot == true
        return motion.title.capitalized + (tagged ? "" : " · auto")
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
                    // An untagged rally opener shows its estimated serve the
                    // way an untagged side shows its call: dashed, marked auto.
                    let estimated = tag.type == nil
                        ? StrokeClassifier.serve(of: event, in: analysis?.events ?? [], convention: convention, tags: tags) : nil
                    ForEach(BadmintonShotType.taggable, id: \.self) { type in
                        chip(type.title + (estimated == type ? " · auto" : ""), on: tag.type == type || estimated == type,
                             firm: tag.type == type) {
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
                Text("Tag a few forehands and backhands; the rest are called for you.")
            }
            LabeledContent("Forehand", value: sideLine(summary.forehand))
            Hairline()
            LabeledContent("Backhand", value: sideLine(summary.backhand))
            if summary.unclear > 0 {
                Hairline()
                LabeledContent("Too close to call", value: "\(summary.unclear)")
            }
            if let stronger = summary.stronger {
                Text("Faster side: \(stronger.title.lowercased())").font(.caption).foregroundStyle(quiet)
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
        panel(session.kind == .match ? "Match" : "Practice", icon: "trophy", solid: solid) {
            if let score = session.score {
                Text(score.winner.map { $0 == .us ? "Won" : "Lost" } ?? "Unfinished")
                    .font(Editorial.headline(28)).foregroundStyle(solid ? .white : jade)
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
    /// The summary strip and the match card are solid ink in light mode.
    private var solid: Bool { scheme == .light }

    private func metric(_ title: String, _ value: String, _ unit: String, onInk: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(onInk ? .white.opacity(0.62) : quiet)
            Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption2).foregroundStyle(onInk ? .white.opacity(0.8) : jade)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
    }
    /// A card on paper, or with `solid` in light mode, ink with white text:
    /// the card is drawn in the dark scheme on the light ink, so its rules
    /// and quiet text resolve light without a second set of colours.
    private func panel<Content: View>(_ title: String, icon: String, solid: Bool = false,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(solid ? .white : jade)
            content().font(.subheadline).foregroundStyle(solid ? .white.opacity(0.75) : quiet)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.colorScheme, solid ? .dark : scheme)
            .background(solid ? LifeOSTokens.primaryText.resolve(.light) : LifeOSTokens.cardSurface.resolve(scheme),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(solid ? .clear : Editorial.rule(scheme)))
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
    var motion: SwingMotion?
    @State private var playback = 0.0
    @State private var playing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var angle: ReplayAngle = .front
    private var duration: Double { event?.duration ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WristCourtReplay(event: event, time: playback, leftHanded: leftHanded, dark: scheme == .dark, motion: motion, angle: angle)
                // Rebuilt when the appearance changes, since the court's
                // colours are set when the scene is made.
                .id(scheme)
                .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .topTrailing) {
                    Label("Drag to turn", systemImage: "hand.draw").font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule()).padding(10)
                        .accessibilityHidden(true)
                }
            HStack(spacing: 6) {
                ForEach(ReplayAngle.allCases, id: \.self) { option in
                    Button(option.title) { angle = option }
                        .buttonStyle(.editorial(angle == option ? .primary : .secondary, size: .compact))
                        .accessibilityAddTraits(angle == option ? .isSelected : [])
                }
            }
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
    /// Paper court and ink lines in light mode, the dark court in dark mode.
    var dark = false
    /// The shot to animate the whole figure through; nil replays the wrist
    /// alone on a still figure.
    var motion: SwingMotion?
    var angle: ReplayAngle = .front

    final class Coordinator { var angle: ReplayAngle? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Where each preset puts the camera, all looking at the player.
    static func place(_ camera: SCNNode, at angle: ReplayAngle) {
        let target = SCNVector3(0.05, 1.05, 3.4)
        switch angle {
        case .front: camera.position = SCNVector3(1.5, 1.85, 0.9)
        case .side: camera.position = SCNVector3(3.7, 1.55, 3.4)
        case .behind: camera.position = SCNVector3(0.9, 2.2, 7.6)
        case .above: camera.position = SCNVector3(0.02, 6.2, 3.45)
        }
        camera.look(at: target)
    }
    /// Where the player stands: on the near half, between the service line
    /// and the back line.
    static let base: SIMD3<Float> = [0, 0, 3.4]

    /// The court's colours for the current appearance. The figure is drawn
    /// the same way in both: white with ink outlines reads on either.
    private struct CourtPalette {
        let background, floor, line, net, tape: UIColor
        static let light = CourtPalette(
            background: UIColor(red: 0.953, green: 0.949, blue: 0.941, alpha: 1),
            floor: UIColor(red: 0.89, green: 0.875, blue: 0.85, alpha: 1),
            line: UIColor(white: 0.1, alpha: 0.85), net: UIColor(white: 0.1, alpha: 0.12),
            tape: UIColor(white: 0.1, alpha: 1))
        static let dark = CourtPalette(
            background: UIColor(red: 0.015, green: 0.075, blue: 0.07, alpha: 1),
            floor: UIColor(red: 0.03, green: 0.17, blue: 0.14, alpha: 1),
            line: UIColor(white: 1, alpha: 0.55), net: UIColor(white: 1, alpha: 0.18),
            tape: UIColor(white: 1, alpha: 0.85))
    }

    func makeUIView(context: Context) -> SCNView {
        let palette = dark ? CourtPalette.dark : CourtPalette.light
        let view = SCNView(); let scene = SCNScene(); view.scene = scene
        view.backgroundColor = palette.background
        view.autoenablesDefaultLighting = true; view.allowsCameraControl = true
        // From the net side, looking back at the player: the face and the
        // racket arm are towards the camera, and the court runs away behind
        // them to the back line. From behind, the figure was its shirt.
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        Self.place(camera, at: angle)
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        context.coordinator.angle = angle
        // A regulation court in metres (BWF Laws, Appendix 1): 13.4 by 6.1
        // for doubles, singles sidelines 0.46 inside, short service lines
        // 1.98 from the net, doubles long service lines 0.76 inside the back
        // line, centre lines from the short service line back.
        let floor = SCNBox(width: 6.5, height: 0.06, length: 13.8, chamferRadius: 0.04)
        floor.firstMaterial?.diffuse.contents = palette.floor
        // Flat like the figure, so the light court reads as paper, not grey.
        floor.firstMaterial?.lightingModel = .constant
        let floorNode = SCNNode(geometry: floor); floorNode.position.y = -0.03
        scene.rootNode.addChildNode(floorNode)
        let halfWidth: Float = 3.05, singles: Float = 2.59, back: Float = 6.7
        for x in [-halfWidth, halfWidth, -singles, singles] { line(scene, palette.line, x: x, z: 0, width: 0.04, length: CGFloat(back * 2)) }
        for z in [-back, back, -5.94, 5.94, -1.98, 1.98] { line(scene, palette.line, x: 0, z: z, width: CGFloat(halfWidth * 2), length: 0.04) }
        let centreLength: Float = back - 1.98
        line(scene, palette.line, x: 0, z: 1.98 + centreLength / 2, width: 0.04, length: CGFloat(centreLength))
        line(scene, palette.line, x: 0, z: -(1.98 + centreLength / 2), width: 0.04, length: CGFloat(centreLength))
        // The net: 1.55 m at the posts, a 0.76 m deep mesh band below the top.
        let net = SCNBox(width: CGFloat(halfWidth * 2), height: 0.76, length: 0.02, chamferRadius: 0)
        net.firstMaterial?.diffuse.contents = palette.net
        let netNode = SCNNode(geometry: net); netNode.position = SCNVector3(0, 1.55 - 0.38, 0); scene.rootNode.addChildNode(netNode)
        let tape = SCNBox(width: CGFloat(halfWidth * 2), height: 0.04, length: 0.03, chamferRadius: 0)
        tape.firstMaterial?.diffuse.contents = palette.tape
        let tapeNode = SCNNode(geometry: tape); tapeNode.position = SCNVector3(0, 1.55, 0); scene.rootNode.addChildNode(tapeNode)
        for x in [-halfWidth, halfWidth] {
            let post = SCNCylinder(radius: 0.03, height: 1.55)
            post.firstMaterial?.diffuse.contents = palette.tape
            let postNode = SCNNode(geometry: post); postNode.position = SCNVector3(x, 0.775, 0); scene.rootNode.addChildNode(postNode)
        }
        let figure = BadmintonFigure.build(leftHanded: leftHanded)
        BadmintonFigure.apply(.ready, to: figure, base: Self.base)
        scene.rootNode.addChildNode(figure)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        // A new preset moves the camera, eased; anything else leaves it where
        // the person dragged it, since this runs on every playback tick.
        if context.coordinator.angle != angle, let camera = view.scene?.rootNode.childNode(withName: "camera", recursively: false) {
            context.coordinator.angle = angle
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.6
            view.pointOfView = camera
            Self.place(camera, at: angle)
            SCNTransaction.commit()
        }
        guard let figure = view.scene?.rootNode.childNode(withName: "figure", recursively: false),
              let wrist = figure.childNode(withName: "wrist", recursively: true) else { return }
        // A known shot: the whole figure plays it, timed over the recorded
        // swing so the playback slider scrubs through it.
        if let motion, let duration = event?.duration, duration > 0 {
            BadmintonFigure.apply(motion.pose(at: Float(time / duration)), to: figure, base: Self.base)
            wrist.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            return
        }
        // Otherwise the still figure in the ready position, with the
        // forearm turned by the recorded wrist orientation.
        BadmintonFigure.apply(.ready, to: figure, base: Self.base)
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
    private func line(_ scene: SCNScene, _ color: UIColor, x: Float, z: Float, width: CGFloat, length: CGFloat) {
        let box = SCNBox(width: width, height: 0.02, length: length, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = color
        box.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: box); node.position = SCNVector3(x, 0.011, z); scene.rootNode.addChildNode(node)
    }
}

/// The replay's camera presets. The view can also be turned by dragging.
enum ReplayAngle: CaseIterable {
    case front, side, behind, above
    var title: String {
        switch self {
        case .front: "Front"
        case .side: "Side"
        case .behind: "Behind"
        case .above: "Above"
        }
    }
}
