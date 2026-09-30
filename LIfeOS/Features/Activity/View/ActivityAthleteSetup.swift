import SwiftUI
import AppSurfaces
import DesignSystem

struct ActivityAthleteSetup: View {
    let initial: ActivityAthleteProfile?
    var onSave: (ActivityAthleteProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var height = ""
    @State private var weight = ""
    @State private var hand: ActivityAthleteProfile.Side = .right
    @State private var wrist: ActivityAthleteProfile.Side = .left
    @State private var enabled = false
    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var profile: ActivityAthleteProfile {
        .init(heightCM: number(height), weightKG: number(weight), playingHand: hand, watchWrist: wrist, motionEnabled: enabled)
    }
    private var valid: Bool {
        profile.isValid && (height.isEmpty || number(height) != nil) && (weight.isEmpty || number(weight) != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Made for your movement.").font(LifeOSType.sectionTitle)
                    Text("Set up once for all activities. Measurements are optional and saved to your account on this device.")
                        .font(LifeOSType.secondary).foregroundStyle(.secondary)
                }
                Section("Your measurements") {
                    HStack { Text("Height"); TextField("Optional", text: $height).multilineTextAlignment(.trailing).keyboardType(.decimalPad); Text("cm").foregroundStyle(.secondary) }
                    HStack { Text("Weight"); TextField("Optional", text: $weight).multilineTextAlignment(.trailing).keyboardType(.decimalPad); Text("kg").foregroundStyle(.secondary) }
                    Text("Height and weight personalize your profile. They cannot determine racket speed or posture.").font(.caption).foregroundStyle(.secondary)
                    if !valid { Text("Enter a height from 80–250 cm and weight from 20–350 kg, or leave them blank.").font(.caption).foregroundStyle(.orange) }
                }
                Section("Badminton · Apple Watch") {
                    Picker("Playing hand", selection: $hand) { ForEach(ActivityAthleteProfile.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("Watch wrist", selection: $wrist) { ForEach(ActivityAthleteProfile.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Toggle("Experimental swing analysis", isOn: $enabled)
                    Text(hand == wrist ? "Wear your Watch securely on your racket wrist. Keep still for one second after starting. Wrist motion is processed on Watch; short orientation traces sync with your workout." : "Swing analysis needs the Watch on your racket wrist. Change your Watch wrist setting when you move it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Counts are estimates, including practice swings. This does not identify shuttle contact, correct technique or court location. WHOOP contributes health data, not swing motion.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save setup") { onSave(profile); dismiss() }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44).disabled(!valid)
            }
            .navigationTitle("Activity setup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .tint(LifeOSTokens.accent)
            .onAppear {
                guard let initial else { return }
                height = initial.heightCM.map { String($0) } ?? ""; weight = initial.weightKG.map { String($0) } ?? ""
                hand = initial.playingHand; wrist = initial.watchWrist; enabled = initial.motionEnabled
            }
        }
    }
}
