import SwiftUI
import DesignSystem

/// The profile photo as a toolbar button.
///
/// Replaces the gear that used to sit here. A gear says "settings"; a face
/// says "you", and everything that was behind the gear now lives behind the
/// face. Falls back to a glyph rather than initials: a single letter in a
/// circle reads as an avatar that failed to load.
struct ProfileAvatar: View {
    let photo: Data?
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LifeOSTokens.cardSurface.resolve(scheme)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
        }
    }
}
