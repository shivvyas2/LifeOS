import SwiftUI
import DesignSystem

/// Photo-led identity, readable activity panels, and explicit account destinations.
struct ProfileOverview: View {
    let profile: LocalProfile
    let photo: Data?
    let stats: [ProfileStat]
    let highlights: [ProfileStat]
    let allTime: [ProfileStat]
    var onEdit: () -> Void
    var onFriends: () -> Void
    var onConnections: () -> Void
    var onSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private var primary: Color { .white }
    private var secondary: Color { .white.opacity(0.75) }
    private var name: String { profile.fullName.isEmpty ? "Make it yours" : profile.fullName }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 760
            ZStack {
                ProfilePhotoBackdrop(photo: photo, showsPortrait: !wide)
                ScrollView {
                    if wide {
                        HStack(alignment: .top, spacing: 28) {
                            identity(width: 340, wide: true).frame(width: 340)
                            details.frame(maxWidth: 540)
                        }
                        .frame(maxWidth: 940)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 40)
                    } else {
                        VStack(spacing: 24) {
                            identity(width: proxy.size.width, wide: false)
                            details
                        }
                        .padding(.horizontal, 24).padding(.bottom, 40)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(primary)
        .tint(LifeOSTokens.accent)
        .environment(\.colorScheme, .dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func identity(width: CGFloat, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                if wide, let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: width, height: 340, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 0.65),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                } else if photo == nil {
                    Text(initials).font(.system(size: 86, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: wide ? 340 : max(200, width * 0.64))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR SPACE").font(.caption2.weight(.semibold)).tracking(1.6)
                    .foregroundStyle(secondary)
                Text(name).font(.largeTitle.bold()).tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(secondary)
                } else if profile.fullName.isEmpty {
                    Text("Start with your name and a photo.").font(.subheadline).foregroundStyle(secondary)
                }
            }
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Label("Edit profile", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 16))
                }
                Button(action: onEdit) {
                    Image(systemName: "camera").font(.body.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityLabel(photo == nil ? "Add profile photo" : "Change profile photo")
            }
            .buttonStyle(.plain)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !stats.isEmpty { summary }
            if !highlights.isEmpty { statPanel("Today", subtitle: "Your latest recorded numbers", items: highlights) }
            if !allTime.isEmpty { statPanel("Over time", subtitle: "All-time totals", items: allTime) }
            if stats.isEmpty && highlights.isEmpty && allTime.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your story starts here", systemImage: "chart.xyaxis.line").font(.headline)
                    Text("Your activity will appear here as you use the app and connect your sources.")
                        .font(.subheadline).foregroundStyle(secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22))
            }
            shortcuts
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your rhythm").font(.title3.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 1 : min(stats.count, 3)), spacing: 16) {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stat.value).font(.title.bold()).monospacedDigit()
                            .foregroundStyle(primary).fixedSize(horizontal: false, vertical: true)
                        Text(stat.label).font(.caption).foregroundStyle(secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22))
    }

    private func statPanel(_ title: String, subtitle: String, items: [ProfileStat]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 135), alignment: .leading)], spacing: 16) {
                ForEach(items) { stat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stat.label).font(.caption).foregroundStyle(secondary)
                        Text(stat.value).font(.title3.weight(.semibold)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22))
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your account").font(LifeOSType.sectionTitle)
            shortcut("Together", detail: "Friends, conversations and a little motivation.", icon: "person.2", action: onFriends)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150))], spacing: 12) {
                shortcut("Connections", detail: "Health, wearables & banks", icon: "link", action: onConnections)
                shortcut("Settings", detail: "Goals & preferences", icon: "slider.horizontal.3", action: onSettings)
            }
        }
    }

    private func shortcut(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: icon).font(.title3).foregroundStyle(LifeOSTokens.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(LifeOSType.rowTitle).foregroundStyle(primary)
                    Text(detail).font(LifeOSType.caption).foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }

    private var initials: String {
        let letters = [profile.firstName, profile.lastName].compactMap { $0.trimmingCharacters(in: .whitespaces).first }
        return letters.isEmpty ? "You" : String(letters.prefix(2)).uppercased()
    }

    private var subtitle: String? {
        var parts: [String] = []
        if !profile.country.isEmpty, let country = Locale.current.localizedString(forRegionCode: profile.country) {
            parts.append(country)
        }
        if let height = profile.heightCM { parts.append("\(Int(height.rounded())) cm") }
        if let birth = profile.birthDate,
           let years = Calendar.current.dateComponents([.year], from: birth, to: .now).year, years > 0 {
            parts.append("\(years) years")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
