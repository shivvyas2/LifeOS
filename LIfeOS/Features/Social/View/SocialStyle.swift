import SwiftUI
import DesignSystem
import Integrations

enum SocialTheme {
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.09)
    static let cream = Color(red: 0.93, green: 0.90, blue: 0.85)
    static let coral = Color(red: 0.98, green: 0.41, blue: 0.30)
    static let mint = Color(red: 0.70, green: 0.83, blue: 0.69)
    static let lilac = Color(red: 0.79, green: 0.74, blue: 0.92)
    static let yellow = Color(red: 0.98, green: 0.81, blue: 0.35)
    static func color(for id: UUID) -> Color {
        let index = id.uuidString.utf8.reduce(0) { ($0 + Int($1)) % 4 }
        return [coral, mint, lilac, yellow][index]
    }
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.14) : .white.opacity(0.72)
    }
}

struct SocialCanvas<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark
                ? [Color(red: 0.14, green: 0.13, blue: 0.11), Color(red: 0.07, green: 0.07, blue: 0.07)]
                : [SocialTheme.cream, Color(red: 0.99, green: 0.98, blue: 0.96)],
                startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            content
        }
        .tint(LifeOSTokens.accent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }
}

struct SocialPanel<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(SocialTheme.paper(scheme), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.045)))
    }
}

struct SocialActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.bold))
            .padding(.horizontal, 18).frame(minHeight: 46)
            .foregroundStyle(scheme == .dark ? SocialTheme.ink : .white)
            .background(scheme == .dark ? Color.white : SocialTheme.ink, in: RoundedRectangle(cornerRadius: 15))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct SocialAvatar: View {
    let profile: SocialProfile
    var size: CGFloat = 44
    @State private var photo: Data?
    var body: some View {
        Group {
            if let photo { ProfileAvatar(photo: photo, size: size) }
            else {
                Text(profile.displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased())
                    .font(.system(size: size * 0.31, weight: .semibold))
                    .foregroundStyle(SocialTheme.ink)
                    .frame(width: size, height: size)
                    .background(SocialTheme.color(for: profile.id), in: Circle())
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: size > 60 ? 5 : 3))
        .accessibilityHidden(true)
        .task(id: profile.avatarPath) {
            photo = nil
            guard let path = profile.avatarPath, let url = AppConfig.supabaseURL,
                  let key = AppConfig.supabaseAnonKey, let token = SocialSession.current?.accessToken else { return }
            let result = try? await ProfileClient(baseURL: url, anonKey: key).downloadAvatar(path: path, accessToken: token)
            guard !Task.isCancelled else { return }
            photo = result
        }
    }
}

struct SocialHeading: View {
    let title: String
    let detail: String
    var icon: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).lifeOSText(.display).tracking(-0.8)
                if !icon.isEmpty { Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(LifeOSTokens.accent).accessibilityHidden(true) }
            }
            Text(detail).lifeOSText(.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SocialNotice: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(LifeOSTokens.accent)
            Text(message).lifeOSText(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Retry", action: retry).font(.subheadline.bold()).frame(minHeight: 44) }
        }
        .padding(16).background(LifeOSTokens.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SocialEmpty: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(LifeOSTokens.accent)
                .padding(.bottom, 4)
            Text(title).lifeOSText(.sectionTitle)
            Text(detail).lifeOSText(.secondary).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity)
    }
}

struct SocialFriendRequest: View {
    let profile: SocialProfile
    var accept: () -> Void
    var decline: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                SocialAvatar(profile: profile, size: 48)
                Text(profile.displayName).lifeOSText(.rowTitle).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                Button("Decline", action: decline).lifeOSText(.secondary).foregroundStyle(.secondary).frame(minHeight: 44)
                Button("Accept", action: accept).buttonStyle(SocialActionStyle())
            }
        }.padding(.vertical, 8)
    }
}
