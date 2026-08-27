import SwiftUI
import PhotosUI
import DesignSystem

/// Who this account belongs to, and everything that configures it.
///
/// Settings used to be a gear in the corner of Today, which put "change the
/// theme" and "sign out" at the same level of prominence as the day itself.
/// This replaces it: the avatar is the way in, the person is the subject of
/// the screen, and the settings sit underneath where someone looking for them
/// will still find them on the first scroll.
///
/// The photo runs full-bleed behind the name, with the card overlapping it.
/// That overlap is the whole shape: a header image with a card butted up
/// beneath it reads as two stacked panels, and the same image with the card
/// pulled up over its lower edge reads as one object.
struct ProfileScreen: View {
    @Bindable var settings: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    var health: HealthConnectionViewModel?
    var plaid: PlaidConnectionViewModel?
    /// The three figures under the name. Passed in rather than computed here,
    /// because this screen owns no data of its own and should not start.
    var stats: [ProfileStat] = []
    var onSignOut: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var photo: Data? = ProfilePhotoStore.load()
    @State private var profile: LocalProfile = ProfileStore.load()
    @State private var isEditing = false

    private var name: String {
        profile.fullName.isEmpty ? "Your profile" : profile.fullName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // The photo and the glass sit in one stack, bottom
                    // aligned, so the panel frosts the photo it is on rather
                    // than a colour behind it. That is the whole effect: you
                    // can still read the image through the blur.
                    ZStack(alignment: .bottom) {
                        hero
                        glassPanel
                    }

                    settingsBlock
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { topControls }
        }
        .onChange(of: settings.draft) { settings.save() }
        .sheet(isPresented: $isEditing) {
            ProfileEditSheet(profile: profile, photo: photo) { newProfile, newPhoto in
                profile = newProfile
                photo = newPhoto
                ProfileStore.save(newProfile)
                ProfilePhotoStore.save(newPhoto)
            }
        }
    }

    /// Circular glass controls in the corners, the way the reference does it.
    /// A bar button would need a bar, and a bar would cut the photo off.
    private var topControls: some View {
        HStack {
            circleButton("xmark", label: "Close") { dismiss() }
            Spacer()
            circleButton("pencil", label: "Edit profile") { isEditing = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    private func circleButton(_ symbol: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(LifeOSType.label.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial.opacity(0.9)))
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
        .accessibilityLabel(label)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // No photo is a state, not a gap: the module gradient stands
                // in so the shape of the screen is the same either way.
                LinearGradient(
                    colors: [ModuleHue.habits.top.opacity(0.85),
                             ModuleHue.recovery.top.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Saturated, not pastel. The pastels are tuned to sit behind
                // text on a light canvas; stretched across 360 points with a
                // scrim over them they turn to grey mush, which reads as an
                // image that failed to load rather than a deliberate state.
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 52, weight: .regular))
                    Text("Add a photo")
                        .font(LifeOSType.secondary.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 54)
            }

        }
        .frame(height: 560)
        // Pinned to the container's width, not the image's.
        //
        // `scaledToFill` makes the image larger than its frame by design, and
        // a ZStack sizes itself to its largest child: with only a height
        // constraint the stack took the scaled image's full width, which made
        // the whole scroll view wider than the screen. Every row below it then
        // centred inside that phantom width and hung off both edges, which is
        // what clipped the name and the section labels.
        .containerRelativeFrame(.horizontal)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            // On the photo rather than in the toolbar: this is the thing
            // people come back to change, and a profile whose picture can
            // only be set once during signup is a profile people ask about.
            Button { isEditing = true } label: {
                Label("Edit", systemImage: "pencil")
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
            .padding(.trailing, 20)
            .padding(.bottom, 46)
        }
    }

    // MARK: - Card

    /// The frosted panel. Dark glass and white ink regardless of appearance,
    /// because it sits on a photograph and a photograph has no light mode.
    private var glassPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if !stats.isEmpty { statRow }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Two layers: the frost, then a dark wash. Frost alone over a
            // bright photo leaves white text unreadable, and a flat dark panel
            // loses the image entirely. Together the photo still shows through
            // and the type still holds.
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(.black.opacity(0.28))
        }
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
        }
    }

    /// The settings, on solid ground below the glass.
    ///
    /// Deliberately not inside the panel: these are light-scheme cards with
    /// their own surfaces, and stacking them on frosted glass over a
    /// photograph makes both unreadable.
    private var settingsBlock: some View {
        SettingsScreen(
            model: settings, whoop: whoop, health: health, plaid: plaid,
            onSignOut: onSignOut
        )
        .sections
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    /// Only what was actually filled in. A profile that pads itself with
    /// placeholder dashes for the fields someone skipped looks broken rather
    /// than optional.
    private var subtitle: String? {
        var parts: [String] = []
        if !profile.country.isEmpty,
           let country = Locale.current.localizedString(forRegionCode: profile.country) {
            parts.append(country)
        }
        if let height = profile.heightCM {
            parts.append("\(Int(height.rounded())) cm")
        }
        if let birth = profile.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birth, to: .now).year ?? 0
            if years > 0 { parts.append("\(years)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The reference puts followers and following here. This app has neither,
    /// and inventing a social number for a private tracker would be a lie in
    /// the most prominent place on the screen. These are what it does know.
    private var statRow: some View {
        HStack(spacing: 0) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.value)
                        .font(LifeOSType.numeral)
                        .foregroundStyle(.white)
                    Text(stat.label)
                        .font(LifeOSType.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One figure under the name.
struct ProfileStat: Identifiable, Equatable {
    let id: String
    let value: String
    let label: String

    init(_ label: String, _ value: String) {
        self.id = label
        self.label = label
        self.value = value
    }
}
