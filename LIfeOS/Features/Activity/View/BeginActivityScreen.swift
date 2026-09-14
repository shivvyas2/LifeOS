import SwiftUI
import DesignSystem
import Integrations

struct BeginActivityScreen: View {
    @Bindable var model: ActivityRecorder
    var onQuickLog: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showSensors = false
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    AccountPageHeading(title: model.saved ? "Time well spent." : model.hasSession ? model.selection.rawValue : "Make time to move.",
                        detail: model.saved ? (model.healthSaved ? "Saved to Almanac and Apple Health." : "Saved to your Almanac account on this device.") : "One activity. Your own pace.")
                    timerCard
                    if !model.hasSession && !model.saved { activityPicker }
                    if model.hasSession { liveReadings }
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
            .background(LifeOSTokens.canvas.resolve(scheme))
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
    private var liveReadings: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = model.isRunning && model.heartRateDate.map { timeline.date.timeIntervalSince($0) < 15 } == true
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                HealthReadingCard(icon: "heart", label: "Heart rate", value: fresh ? model.heartRate.map { String(Int($0)) } : nil,
                    unit: "bpm", caption: fresh ? "Live sensor reading" : model.isPaused ? "Activity paused" : "Waiting for a sensor", hue: .habits)
                HealthReadingCard(icon: "flame", label: "Active energy", value: model.energy.map { String(Int($0)) },
                    unit: "kcal", caption: model.energy == nil ? "No energy reading" : "From Apple Health", hue: .activity)
                HealthReadingCard(icon: "point.bottomleft.forward.to.point.topright.scurvepath", label: "Distance",
                    value: model.distance.map { String(format: "%.2f", $0 / 1000) }, unit: "km", caption: model.distance == nil ? "No distance reading" : "From Apple Health", hue: .body)
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
                Text(model.sensor.status).font(LifeOSType.caption).foregroundStyle(.secondary)
                DisclosureGroup("How syncing works") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHOOP: turn on Heart Rate Broadcast, then connect its Bluetooth sensor here for live beats.")
                        Text("Apple Health: this session saves with your permission. Apple Watch workouts appear when the watch writes to Health; this screen does not control Apple's Workout app.")
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
