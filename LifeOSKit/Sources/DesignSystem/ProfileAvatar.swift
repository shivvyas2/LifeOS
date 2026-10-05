import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The signed-in person, as a small circle. Shared by the shell bar and the
/// social screens, so it lives in the package rather than beside one of them.
public struct ProfileAvatar: View {
    public let photo: Data?
    public var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    public init(photo: Data?, size: CGFloat = 30) {
        self.photo = photo; self.size = size
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1) }
    }

    private var placeholder: some View {
        LifeOSTokens.cardSurface.resolve(scheme)
            .overlay {
                Image(systemName: "person.fill")
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
    }
}
