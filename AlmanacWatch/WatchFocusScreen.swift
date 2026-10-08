import SwiftUI

/// A focus session on the wrist: only the heart rate the phone's
/// soundscape is listening to, and a way to stop.
struct WatchFocusScreen: View {
    let workout: WatchWorkoutController

    var body: some View {
        VStack(spacing: 8) {
            Text("Focus").font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                Text(workout.heartRate.map(String.init) ?? "--").font(.system(.title, design: .rounded).monospacedDigit())
            }
            Text("Heart rate shapes the sound on your iPhone.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Stop") { workout.discard() }.tint(.secondary)
        }
        .padding()
    }
}
