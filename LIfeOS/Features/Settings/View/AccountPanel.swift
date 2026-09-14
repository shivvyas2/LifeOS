import SwiftUI
import DesignSystem

struct AccountPanel<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AccountPageHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(LifeOSType.screenTitle)
            Text(detail).font(LifeOSType.secondary).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}
