import SwiftUI
import DesignSystem
import Integrations
import AppSurfaces

struct BeginActivityScreen: View {
    @Bindable var model: ActivityRecorder
    var onQuickLog: () -> Void = {}
    /// The design fixture folds the rings into the bar so both states can be captured.
    var startsCollapsed = false
    /// The workout library, when the app supplies it. Nil in the design
    /// preview's plain recorder page, which has no library to push.
    var library: WorkoutLibraryViewModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSensors = false
    @State private var showAthleteSetup = false
    @State private var hudExpanded = true
    @State private var showAllActivities = false
    @State private var width: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { _ in EmptyView() }.frame(height: 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                if sizeClass == .regular, width >= 900 {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 22) { leading }.frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 22) { trailing }.frame(maxWidth: 420, alignment: .topLeading)
                    }
                    .padding(22).padding(.bottom, 20)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        leading
                        trailing
                    }
                    .frame(maxWidth: 620).frame(maxWidth: .infinity).padding(22).padding(.bottom, 20)
                }
            }
            // Plain paper behind everything; the live state is the ember
            // field in the hero now, not a blue wash across the top.
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(model.hasSession ? "Activity" : "Begin activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        // Ink, not the accent: a screen-wide accent tint made every plain
        // control orange, and the accent is kept for live and urgent things.
        .tint(LifeOSTokens.primaryText.resolve(scheme))
        .onAppear { if startsCollapsed { hudExpanded = false } }
        .sheet(isPresented: $showAthleteSetup) { ActivityAthleteSetup(initial: model.athlete, onSave: model.saveAthlete) }
        .sheet(isPresented: $showSensors, onDismiss: { model.sensor.stopScan() }) { sensorSheet }
    }

    /// The session itself: hero or timer, the tiles, the picker.
    @ViewBuilder private var leading: some View {
        if model.hasSession, let readout = model.readout {
            if model.source == .demo { demoBanner }
            liveHero(readout)
            if model.selection.name == ActivityRecorder.badminton, model.badminton?.kind != .practice {
                BadmintonScoreCard(model: model)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LiveReadings(model: model, readout: readout, link: liveLink(at: timeline.date), now: timeline.date)
            }
        } else {
            EditorialMasthead(eyebrow: model.saved ? (model.source == .demo ? "Demo · finished" : "Activity · saved") : "Activity",
                title: model.saved ? (model.source == .demo ? "That was the demo." : "Time well spent.") : "Make time to move.",
                detail: model.saved
                    ? (model.source == .demo ? "Nothing was saved. For the real thing, wear your Watch on your racket wrist with swing analysis on."
                       : model.healthSaved ? "Saved to Almanac and Apple Health." : "Saved to your Almanac account on this device.")
                    : "One activity. Your own pace.")
            timerCard
            if !model.saved {
                if let library { followVideoLink(library) }
                activityPicker
                if model.selection.name == ActivityRecorder.badminton {
                    BadmintonSetupCard(setup: $model.badmintonSetup)
                    swingAnalysisLine
                }
                VStack(spacing: 0) {
                    Button { showAthleteSetup = true } label: { Label("Your activity setup", systemImage: "figure.stand") }
                        .buttonStyle(.editorial(.quiet, fullWidth: true))
                    if model.selection.name == ActivityRecorder.badminton {
                        Button { model.startDemo() } label: { Label("Try the demo", systemImage: "play.circle") }
                            .buttonStyle(.editorial(.secondary, fullWidth: true)).disabled(model.busy)
                        NavigationLink { BadmintonHistoryScreen(onDemo: { model.startDemo() }) } label: {
                            Label("Past badminton sessions", systemImage: "figure.badminton")
                        }
                        .buttonStyle(.editorial(.quiet, fullWidth: true))
                    } else {
                        NavigationLink { BadmintonHistoryScreen() } label: { Label("Past badminton sessions", systemImage: "figure.badminton") }
                            .buttonStyle(.editorial(.quiet, fullWidth: true))
                    }
                }
            }
        }
        if let notice = model.notice { Text(notice).font(LifeOSType.caption).foregroundStyle(.secondary) }
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(LifeOSType.secondary).foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
        }
    }
    /// Controls, connections and the quick log: beside the session on a
    /// wide screen, under it otherwise.
    @ViewBuilder private var trailing: some View {
        if model.saved && model.selection.name == "Badminton" {
            if model.source == .demo, let review = model.demoReview {
                NavigationLink { BadmintonReviewScreen(workout: review) } label: { Label("Review the demo", systemImage: "chart.xyaxis.line") }
                    .buttonStyle(.editorial(.primary, fullWidth: true))
            } else {
                // The session just finished, not the list it belongs to.
                NavigationLink { BadmintonLatestReview(externalID: model.savedRecordID) } label: { Label("Review your session", systemImage: "chart.xyaxis.line") }
                    .buttonStyle(.editorial(.primary, fullWidth: true))
            }
        }
        ActivityControls(model: model, onDone: { dismiss() })
        if !model.saved { connections }
        if !model.hasSession && !model.saved {
            Button { dismiss(); onQuickLog() } label: {
                Label("Log steps, weight or a reflection", systemImage: "square.and.pencil")
            }.buttonStyle(.editorial(.quiet, fullWidth: true))
        }
    }

    /// The resting timer on the dusk field, the screen's one hero: the
    /// orange pastel card it replaces was a fourth palette on one screen.
    private var timerCard: some View {
        EditorialField(.dusk) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.saved ? "Complete" : model.isPaused ? "Paused" : model.isRunning ? "In progress" : "Ready when you are")
                    .font(LifeOSType.eyebrow).tracking(1.2).textCase(.uppercase).opacity(0.75)
                Spacer()
                Image(systemName: model.selection.symbol).font(.title2).accessibilityHidden(true)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(duration(model.timer?.elapsed(at: timeline.date) ?? 0))
                    .font(Editorial.figure(88)).tracking(Editorial.figureTracking(88)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityLabel("Elapsed time, \(duration(model.timer?.elapsed(at: timeline.date) ?? 0))")
            }
            HStack {
                Text(model.selection.name).font(LifeOSType.rowTitle)
                Spacer()
                Text("Elapsed time").font(LifeOSType.caption).opacity(0.75)
            }
        }
    }
    /// A session in progress, on the ember field: the one place in the app
    /// the accent fills a whole block, because this is the one thing that is
    /// happening right now.
    private func liveHero(_ readout: LiveSessionReadout) -> some View {
        EditorialField(.ember) {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.selection.name, systemImage: model.selection.symbol).font(LifeOSType.rowTitle)
                Spacer()
                Text(readout.isPaused ? "Paused" : readout.push.headline).font(LifeOSType.label)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LiveLinkLine(link: liveLink(at: timeline.date))
            }
            if let following = model.following {
                Text("Following: \(following.title) · \(following.channel)")
                    .font(LifeOSType.caption).opacity(0.85).lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(duration(model.timer?.elapsed(at: timeline.date) ?? 0))
                    .font(Editorial.figure(88)).tracking(Editorial.figureTracking(88)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityLabel("Elapsed time, \(duration(model.timer?.elapsed(at: timeline.date) ?? 0))")
            }
            Text("Elapsed time").font(LifeOSType.caption).opacity(0.85)
            SessionRings(readout: readout, activity: model.selection, zonesAvailable: model.zonesAvailable,
                         countsAutomatically: model.source == .watch,
                         onAddRep: { model.addRep() }, onRemoveRep: { model.removeRep() },
                         onNextSet: { model.nextSet() }, isExpanded: $hudExpanded)
                .fixedSize()
                .padding(.top, 10)
        }
        }
    }

    /// Whether the Watch will analyze swings on the next badminton workout,
    /// and if not, the one thing to change. Said here, before Start, rather
    /// than left to the Watch's "off" afterwards.
    private var swingAnalysisLine: some View {
        let status = SwingAnalysisStatus.describe(model.athlete)
        return HStack(alignment: .top, spacing: Space.x1) {
            Circle().fill(status.isOn ? LifeOSTokens.pushEasy : Editorial.quietInk(scheme))
                .frame(width: 8, height: 8).padding(.top, 5)
            Text(status.text).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
        }
        .accessibilityElement(children: .combine)
    }

    /// The demo says it is one, and says how to get the real thing.
    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Demo").editorialEyebrow()
            Text("Simulated Watch data: the swings, the score and the heart rate are scripted. For the real thing:")
                .font(LifeOSType.secondary).foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                demoStep(1, "Turn on experimental swing analysis in Your activity setup.")
                demoStep(2, "Set Watch wrist to your playing hand.")
                demoStep(3, "Wear the Watch on that wrist, start Badminton, and hold still for a second.")
            }
        }
        .editorialCard()
    }
    private func demoStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Text(String(format: "%02d", number)).font(LifeOSType.caption).monospacedDigit()
                .foregroundStyle(Editorial.quietInk(scheme))
            Text(text).font(LifeOSType.caption).foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where this session's readings come from and whether they are live.
    private func liveLink(at date: Date) -> LiveLink {
        LiveLink.assess(watchOwned: model.source == .watch, watchReachable: !model.watchUnreachable,
                        lastWatchPacket: model.lastWatchPacketAt, sensorName: model.sensor.connectedName,
                        lastHeartRate: model.heartRateDate, paused: model.isPaused, now: date)
    }

    /// Above the picker, because choosing a video is choosing the activity
    /// too: the player maps the split onto the recorder's selection.
    private func followVideoLink(_ library: WorkoutLibraryViewModel) -> some View {
        NavigationLink {
            WorkoutLibraryScreen(model: library, recorder: model)
        } label: {
            Label("Follow a video", systemImage: "play.rectangle")
        }
        .buttonStyle(.editorial(.secondary, fullWidth: true))
        .disabled(model.busy)
    }

    /// The last six activities started, or the six the app always offered
    /// when the account has none yet, then a tile that opens everything.
    /// The current selection is always on the grid, even when it is not a
    /// recent, so the picked activity is never invisible.
    private var pickerTiles: [ActivityType] {
        var tiles = model.recents.types()
        if tiles.isEmpty { tiles = ActivityCatalog.popular }
        if !tiles.contains(model.selection) { tiles.append(model.selection) }
        return tiles
    }
    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your activity").font(LifeOSType.sectionTitle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                ForEach(pickerTiles) { activity in
                    pickerTile(activity.name, symbol: activity.symbol, selected: model.selection == activity) {
                        model.selection = activity
                    }
                }
                pickerTile("More", symbol: "ellipsis.circle", selected: false) { showAllActivities = true }
                    .accessibilityLabel("More activities")
            }
        }
        .sheet(isPresented: $showAllActivities) {
            ActivityPickerSheet(selection: $model.selection)
        }
    }
    private func pickerTile(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                Text(title).font(LifeOSType.rowTitle).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(16).frame(maxWidth: .infinity, minHeight: 58)
            // Selected is an ink outline, not a tint: the editorial way to
            // mark the chosen one, and legible in both schemes.
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? LifeOSTokens.primaryText.resolve(scheme) : Editorial.rule(scheme),
                                            lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain).disabled(model.busy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var connections: some View {
        AccountPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Live heart rate", systemImage: "waveform.path.ecg").font(LifeOSType.rowTitle)
                    Spacer()
                    Button(model.sensor.connectedName == nil ? "Connect" : "Manage") { showSensors = true }
                        .buttonStyle(.editorial(.secondary, size: .compact))
                }
                Text(model.source == .watch ? "Apple Watch is recording this session."
                     : model.source == .demo ? "The demo is standing in for your Apple Watch."
                     : WatchSessionBridge.watchAvailable ? "Apple Watch ready" : "Apple Watch not nearby")
                    .font(LifeOSType.caption).foregroundStyle(.secondary)
                Text(model.sensor.status).font(LifeOSType.caption).foregroundStyle(.secondary)
                DisclosureGroup("How syncing works") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHOOP: turn on Heart Rate Broadcast, then connect its Bluetooth sensor here for live beats.")
                        Text("Apple Watch: when your watch is nearby it records the workout and counts reps; otherwise this iPhone records.")
                        Text("Fitbit and WHOOP cloud readings refresh after the device syncs. They are not live heart-rate feeds.")
                    }.font(LifeOSType.caption).foregroundStyle(.secondary).padding(.top, 8)
                }.font(LifeOSType.label)
            }
        }
    }
    private var sensorSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Turn on Heart Rate Broadcast in WHOOP, or put a Bluetooth heart-rate sensor in pairing mode.")
                    Text(model.sensor.status).foregroundStyle(.secondary)
                    Button(model.sensor.scanning ? "Searching…" : "Find sensors") { model.sensor.scan() }
                        .disabled(model.sensor.scanning)
                    ForEach(model.sensor.devices) { device in
                        Button(device.name) { model.sensor.connect(device) }
                    }
                    if model.sensor.connectedName != nil {
                        Button("Disconnect sensor", role: .destructive) { model.sensor.disconnect() }
                    }
                }
            }
            .navigationTitle("Heart-rate sensor").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSensors = false } } }
        }
    }
    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
