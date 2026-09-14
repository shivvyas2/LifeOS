#if DEBUG
import SwiftUI

/// Isolated visual fixtures; sample values are never written to the account store.
struct ProfileDesignPreview: View {
    @State private var empty = false
    @State private var usePhoto = true
    @State private var largeText = false
    @State private var editing = false

    private var sample: LocalProfile {
        var profile = LocalProfile()
        profile.firstName = "Alex"
        profile.lastName = "Morgan"
        profile.country = "US"
        profile.heightCM = 175
        return profile
    }

    // A generated color fixture, not a real person's photo or account data.
    private static let sampleImage: Data? = {
        UIGraphicsImageRenderer(size: CGSize(width: 480, height: 640)).jpegData(withCompressionQuality: 0.9) { renderer in
            let context = renderer.cgContext
            let colors = [UIColor(red: 0.13, green: 0.62, blue: 0.63, alpha: 1).cgColor,
                          UIColor(red: 0.08, green: 0.27, blue: 0.39, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 480, y: 640), options: [])
            }
            UIImage(systemName: "person.crop.circle.fill")?
                .withTintColor(.white.withAlphaComponent(0.7), renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 120, y: 100, width: 240, height: 240))
        }
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SAMPLE PROFILE").font(.caption2)
                Spacer()
                Toggle("Empty", isOn: $empty).labelsHidden().accessibilityLabel("Empty profile")
                Toggle("Photo", isOn: $usePhoto).labelsHidden().accessibilityLabel("Sample illustration")
                Toggle("Large", isOn: $largeText).labelsHidden().accessibilityLabel("Large text")
            }
            .padding(.horizontal, 20).padding(.vertical, 6)
            NavigationStack {
                ProfileOverview(profile: empty ? LocalProfile() : sample, photo: empty || !usePhoto ? nil : Self.sampleImage,
                                stats: empty ? [] : [.init("Day streak", "12"), .init("Days tracked", "64"), .init("Workouts", "28")],
                                highlights: empty ? [] : [.init("Steps", "8,420"), .init("Sleep", "7h 24m"), .init("Recovery", "72%"), .init("Weight", "74.2 kg")],
                                allTime: empty ? [] : [.init("Steps", "428,610"), .init("Workouts", "28")],
                                onEdit: { editing = true }, onFriends: {}, onConnections: {}, onSettings: {})
                    .navigationTitle("Profile")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(largeText ? .accessibility1 : .large)
        .sheet(isPresented: $editing) {
            ProfileEditSheet(profile: empty ? LocalProfile() : sample, photo: empty || !usePhoto ? nil : Self.sampleImage, onSave: { _, _ in })
        }
    }
}

#Preview { ProfileDesignPreview() }
#endif
