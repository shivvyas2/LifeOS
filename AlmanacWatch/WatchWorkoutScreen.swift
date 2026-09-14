import SwiftUI

/// The wrist view of a running workout: timer, heart rate with a zone chip,
/// reps and set for strength, pause and end.
struct WatchWorkoutScreen: View {
    let workout: WatchWorkoutController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(workout.activityName).font(.headline)
                if let startedAt = workout.startedAt, workout.state == .running {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                } else {
                    Text(statusText).font(.title3)
                }
                if let lastError = workout.lastError {
                    Text(lastError).font(.caption2).foregroundStyle(.orange)
                }
                if workout.mirroringFailed {
                    Text("Not connected to iPhone").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(workout.heartRate.map(String.init) ?? "—").font(.title2.monospacedDigit())
                    if let max = workout.maxHeartRate, let bpm = workout.heartRate {
                        Text("Z\(zone(bpm: bpm, max: max))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if workout.isStrength {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(workout.reps ?? 0)").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("reps · auto").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Set \(workout.setIndex ?? 1)").font(.caption)
                    }
                    if workout.state != .ending {
                        HStack {
                            Button("+1") { workout.addRep() }
                            Button("Next set") { workout.nextSet() }
                        }.tint(.orange)
                    }
                }
                HStack {
                    if workout.state == .paused { Button("Resume") { workout.resume() } }
                    else { Button("Pause") { workout.pause() } }
                    Button("End", role: .destructive) { workout.end() }
                }
            }.padding(.horizontal, 4)
        }
        .navigationTitle("Workout")
    }

    private var statusText: String {
        switch workout.state {
        case .starting: return "Starting…"
        case .paused: return "Paused"
        case .ending: return "Ending…"
        case .idle, .running: return "—"
        }
    }

    /// The five band starts from spec 3.1 of slice 1, duplicated because the
    /// watch does not link `Integrations` and so cannot see `HeartRateZones`.
    private func zone(bpm: Int, max: Int) -> Int {
        let fraction = Double(bpm) / Double(max)
        switch fraction { case ..<0.5: return 0; case ..<0.6: return 1; case ..<0.7: return 2; case ..<0.8: return 3; case ..<0.9: return 4; default: return 5 }
    }
}
