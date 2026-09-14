import SwiftUI
import DesignSystem

struct ProfileActivitySharingCard: View {
    @Binding var isOn: Bool
    var isBusy = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2).foregroundStyle(LifeOSTokens.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("A little of your progress").font(LifeOSType.sectionTitle)
                    Text("On your profile · friends only").font(LifeOSType.caption).foregroundStyle(.secondary)
                }
            }
            Text("Let your friends see your streak, days tracked and total workouts.")
                .font(LifeOSType.secondary).foregroundStyle(.secondary)
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share activity").font(LifeOSType.rowTitle)
                    Text(isOn ? "Visible to accepted friends" : "Only visible to you")
                        .font(LifeOSType.caption).foregroundStyle(.secondary)
                }
            }
            .tint(LifeOSTokens.accent).disabled(isBusy)
            Divider()
            Label("Health scores are shared separately in each group.", systemImage: "lock")
                .font(LifeOSType.caption).foregroundStyle(.secondary)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 26))
    }
}
