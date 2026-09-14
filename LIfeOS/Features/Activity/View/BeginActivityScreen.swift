import SwiftUI
import DesignSystem
import Integrations
import AppSurfaces

struct BeginActivityScreen: View {
    @Bindable var model: ActivityRecorder
    var onQuickLog: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showSensors = false
    @State private var confirmDiscard = false
    @State private var hudExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.hasSession, let readout = model.readout {
                        liveHero(readout)
                        liveTiles(readout)
                    } else {
                        AccountPageHeading(title: model.saved ? "Time well spent." : "Make time to move.",
                            detail: model.saved ? (model.healthSaved ? "Saved to Almanac and Apple Health." : "Saved to your Almanac account on this device.") : "One activity. Your own pace.")
                        timerCard
                        if !model.saved { activityPicker }
                    }
                    if let notice = model.notice { Text(notice).font(LifeOSType.caption).foregroundStyle(.secondary) }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(LifeOSType.secondary).foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                    }
                    controls
                    if !model.saved { connections }
                    if !model.hasSession && !model.saved {
                        Button { dismiss(); onQuickLog() } label: {
                            Label("Log steps, weight or a reflection", systemImage: "square.and.pencil")
                                .font(LifeOSType.label).frame(maxWidth: .infinity, minHeight: 48)
                        }.tint(LifeOSTokens.accent)
                    }
                }
                .frame(maxWidth: 620).frame(maxWidth: .infinity).padding(22).padding(.bottom, 20)
            }
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
                    if model.hasSession {
                        LinearGradient(colors: [scheme == .dark ? ModuleHue.recovery.darkTop : LifeOSTokens.liveGradientTop,
                                                LifeOSTokens.canvas.resolve(scheme)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 380).ignoresSafeArea(edges: .top)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(model.hasSession ? .dark : nil, for: .navigationBar)
            .navigationTitle(model.hasSession ? "Activity" : "Begin activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .tint(LifeOSTokens.accent)
        .sheet(isPresented: $showSensors, onDismiss: { model.sensor.stopScan() }) { sensorSheet }
        .confirmationDialog("Discard this activity?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard activity", role: .destructive) { model.discard() }
        } message: { Text("This timer and its unsaved readings will be removed.") }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(model.saved ? "Complete" : model.isPaused ? "Paused" : model.isRunning ? "In progress" : "Ready when you are",
                      systemImage: model.saved ? "checkmark.circle" : "timer")
                    .font(LifeOSType.label)
                Spacer()
                Image(systemName: model.selection.icon).font(.title2).accessibilityHidden(true)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(duration(model.timer?.elapsed(at: timeline.date) ?? 0))
                    .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityLabel("Elapsed time, \(duration(model.timer?.elapsed(at: timeline.date) ?? 0))")
            }
            Text("Elapsed time").font(LifeOSType.caption)
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme == .dark ? ModuleHue.activity.pastelDark : ModuleHue.activity.pastel,
                    in: RoundedRectangle(cornerRadius: 28))
    }
    private func liveHero(_ readout: LiveSessionReadout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.selection.rawValue, systemImage: model.selection.icon).font(LifeOSType.rowTitle)
                Spacer()
                Text(readout.isPaused ? "Paused" : readout.push.headline).font(LifeOSType.label)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(duration(model.timer?.elapsed(at: timeline.date) ?? 0))
                    .font(.system(size: 72, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityLabel("Elapsed time, \(duration(model.timer?.elapsed(at: timeline.date) ?? 0))")
            }
            Text("Elapsed time").font(LifeOSType.caption).opacity(0.85)
            SessionHUD(readout: readout, activity: model.selection, zonesAvailable: model.zonesAvailable, showsTimer: false,
                       onAddRep: { model.addRep() }, onNextSet: { model.nextSet() }, isExpanded: $hudExpanded)
                .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private func liveTiles(_ readout: LiveSessionReadout) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = model.isRunning && model.heartRateDate.map { timeline.date.timeIntervalSince($0) < 15 } == true
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                glassTile(icon: "heart.fill", label: readout.zone.map { "Heart rate · Z\($0)" } ?? "Heart rate",
                          value: fresh ? readout.heartRateText : nil, unit: "bpm",
                          caption: fresh ? (model.source == .watch ? "From Apple Watch" : "Live sensor reading") : model.isPaused ? "Activity paused" : model.sensor.status)
                if model.zonesAvailable, model.selection != .yoga {
                    glassTile(icon: "bolt.fill", label: "Effort, estimated", value: readout.effortText,
                              unit: readout.ceilingTarget.map { "of \(Int($0.upperBound))" },
                              caption: capacityCaption(readout))
                }
                if model.selection == .strength {
                    glassTile(icon: "repeat", label: readout.setText ?? "Reps", value: readout.repsText, unit: "reps",
                              caption: model.completedSets.isEmpty ? "Counted from your wrist · auto" : "Sets so far: \(model.completedSets.map(String.init).joined(separator: ", "))")
                }
                glassTile(icon: "flame.fill", label: "Calories", value: readout.caloriesText, unit: "kcal",
                          caption: readout.calories == nil ? "No energy reading" : "From Apple Health")
                if [.walk, .run, .cycle].contains(model.selection) {
                    glassTile(icon: "point.bottomleft.forward.to.point.topright.scurvepath", label: "Distance",
                              value: readout.distanceKilometresText, unit: "km",
                              caption: readout.distanceMeters == nil ? "No distance reading" : "From Apple Health")
                }
                if !model.zonesAvailable {
                    Text("Add your birth date in Profile for zones, effort and battery.")
                        .font(LifeOSType.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func capacityCaption(_ readout: LiveSessionReadout) -> String {
        readout.capacitySource == nil ? "Battery unknown · cautious target" : "Battery \(readout.batteryText ?? LiveSessionReadout.missing) · \(readout.capacitySourceName)"
    }

    private func glassTile(icon: String, label: String, value: String?, unit: String?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(label, systemImage: icon).font(LifeOSType.label).opacity(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? LiveSessionReadout.missing).font(.title.bold()).monospacedDigit()
                if let unit, value != nil { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }.lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption.weight(.medium)).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your activity").font(LifeOSType.sectionTitle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                ForEach(RecordedActivity.allCases) { activity in
                    Button { model.selection = activity } label: {
                        HStack {
                            Image(systemName: activity.icon)
                            Text(activity.rawValue).font(LifeOSType.rowTitle)
                            Spacer(minLength: 0)
                            if model.selection == activity { Image(systemName: "checkmark").font(.caption.bold()) }
                        }
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .padding(16).frame(maxWidth: .infinity, minHeight: 58)
                        .background(model.selection == activity ? LifeOSTokens.accentSoft.resolve(scheme) : LifeOSTokens.cardSurface.resolve(scheme),
                                    in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain).disabled(model.busy)
                    .accessibilityAddTraits(model.selection == activity ? .isSelected : [])
                }
            }
        }
    }
    private var controls: some View {
        VStack(spacing: 12) {
            if model.saved {
                primaryButton("Done", icon: "checkmark") { model.discard(); dismiss() }
            } else if model.hasSession {
                if model.timer?.phase != .finished {
                    primaryButton(model.isPaused ? "Resume activity" : "Pause activity", icon: model.isPaused ? "play.fill" : "pause.fill") {
                        model.togglePause()
                    }
                }
                Button { Task { await model.finish() } } label: {
                    Label(model.busy ? "Saving…" : "Finish & save", systemImage: "checkmark")
                        .font(LifeOSType.rowTitle).frame(maxWidth: .infinity, minHeight: 54)
                }.buttonStyle(.bordered).disabled(model.busy)
                Button("Discard activity", role: .destructive) { confirmDiscard = true }
                    .font(LifeOSType.label).frame(minHeight: 44).disabled(model.busy)
            } else {
                Toggle("Save to Apple Health", isOn: $model.saveToHealth).font(LifeOSType.rowTitle)
                    .disabled(model.busy)
                primaryButton(model.busy ? "Starting…" : "Begin activity", icon: "play.fill") {
                    Task { await model.start() }
                }
            }
        }
    }
    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Spacer(); if model.busy { ProgressView() } else { Image(systemName: icon) }; Text(title); Spacer() }
                .font(LifeOSType.rowTitle).frame(minHeight: 56)
                .foregroundStyle(.white).background(LifeOSTokens.accent, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(model.busy)
    }
    private var connections: some View {
        AccountPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Live heart rate", systemImage: "waveform.path.ecg").font(LifeOSType.rowTitle)
                    Spacer()
                    Button(model.sensor.connectedName == nil ? "Connect" : "Manage") { showSensors = true }
                        .font(LifeOSType.label).frame(minHeight: 44)
                }
                Text(model.source == .watch ? "Apple Watch is recording this session." : WatchSessionBridge.watchAvailable ? "Apple Watch ready" : "Apple Watch not nearby")
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
