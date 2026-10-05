import SwiftUI
import DesignSystem
import Integrations

/// The recorder's buttons: begin, pause or resume, finish and save, discard,
/// and Done once a session is written.
///
/// Extracted from Begin Activity so the player screen offers exactly the same
/// controls in the same order. Two screens that both stop a workout should not
/// disagree about what stopping looks like, and the confirm-discard dialog
/// travels with the button that raises it.
struct ActivityControls: View {
    @Bindable var model: ActivityRecorder
    /// Called after Done, once the saved session has been cleared away. Begin
    /// Activity dismisses its sheet; the player pops back to the library.
    var onDone: () -> Void

    @State private var confirmDiscard = false
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 12) {
            if model.saved {
                primaryButton("Done", icon: "checkmark") { model.discard(); onDone() }
            } else if model.hasSession {
                if model.timer?.phase != .finished {
                    primaryButton(model.isPaused ? "Resume activity" : "Pause activity",
                                  icon: model.isPaused ? "play.fill" : "pause.fill") {
                        model.togglePause()
                    }
                }
                Button { Task { await model.finish() } } label: {
                    Label(model.busy ? "Saving…" : "Finish & save", systemImage: "checkmark")
                        .font(LifeOSType.rowTitle).frame(maxWidth: .infinity, minHeight: 54)
                }.buttonStyle(.bordered).disabled(model.busy)
                // Offered only when the watch cannot be asked: disconnected,
                // or a Finish that never got an answer. The workout keeps
                // recording on the wrist and replaces this one when it syncs.
                if model.source == .watch, model.watchUnreachable || model.error != nil {
                    Button { Task { await model.finishOnPhone() } } label: {
                        Label("End on iPhone", systemImage: "iphone")
                            .font(LifeOSType.rowTitle).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered)
                }
                Button("Discard activity", role: .destructive) { confirmDiscard = true }
                    .font(LifeOSType.label).frame(minHeight: 44).disabled(model.busy)
            } else {
                Toggle("Save to Apple Health", isOn: $model.saveToHealth).font(LifeOSType.rowTitle)
                    .disabled(model.busy)
                primaryButton(model.busy ? "Starting…" : "Begin activity", icon: "play.fill") {
                    if model.athlete == nil { showSetup = true } else { Task { await model.start() } }
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            ActivityAthleteSetup(initial: model.athlete) { profile in
                model.saveAthlete(profile)
                Task { await model.start() }
            }
        }
        .confirmationDialog("Discard this activity?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard activity", role: .destructive) { model.discard() }
        } message: { Text("This timer and its unsaved readings will be removed.") }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Spacer(); if model.busy { ProgressView() } else { Image(systemName: icon) }; Text(title); Spacer() }
                .font(LifeOSType.rowTitle).frame(minHeight: 56)
                .foregroundStyle(.white).background(LifeOSTokens.accent, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(model.busy)
    }
}
