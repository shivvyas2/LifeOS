import SwiftUI
import PhotosUI
import DesignSystem

/// Who this account belongs to, full page.
///
/// The photo owns the entire screen and the content sits on a progressive
/// blur of the photo itself — the image melts into frost toward the bottom
/// rather than being covered by a panel, which is what keeps it one object.
/// Settings moved out to their own page behind the gear: the person is the
/// subject here, configuration is a place you go.
struct ProfileScreen: View {
    @Bindable var settings: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    var health: HealthConnectionViewModel?
    var plaid: PlaidConnectionViewModel?
    /// The three figures under the name. Passed in rather than computed here,
    /// because this screen owns no data of its own and should not start.
    var stats: [ProfileStat] = []
    /// Today's living numbers, shown in a glass panel below the stats. Only
    /// what the app actually knows right now; missing data is simply absent.
    var highlights: [ProfileStat] = []
    /// Lifetime aggregates in a second panel: what all that tracking adds up
    /// to. Same rule: only non-zero facts appear.
    var allTime: [ProfileStat] = []
    var onSignOut: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var photo: Data? = ProfilePhotoStore.load()
    @State private var profile: LocalProfile = ProfileStore.load()
    @State private var isEditing = false
    @State private var showSettings = false

    private var name: String {
        profile.fullName.isEmpty ? "Your profile" : profile.fullName
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    heroLayer(size: geo.size)
                    content
                        .padding(.horizontal, 24)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 56)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) { topControls }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) {
                SettingsScreen(
                    model: settings, whoop: whoop, health: health, plaid: plaid,
                    onSignOut: onSignOut
                )
            }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditSheet(profile: profile, photo: photo) { newProfile, newPhoto in
                profile = newProfile
                photo = newPhoto
                ProfileStore.save(newProfile)
                ProfilePhotoStore.save(newPhoto)
            }
        }
    }

    // MARK: - The photo, twice

    /// The sharp photo, then the same photo blurred and masked so it takes
    /// over gradually below the midline, then a quiet dark wash for the type.
    /// No panel: the frost IS the image.
    @ViewBuilder
    private func heroLayer(size: CGSize) -> some View {
        ZStack {
            photoLayer(size: size)

            photoLayer(size: size)
                .blur(radius: 38, opaque: true)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.38),
                            .init(color: .black, location: 0.62),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.38), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipped()
    }

    @ViewBuilder
    private func photoLayer(size: CGSize) -> some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
        } else {
            // No photo is a state, not a gap: the module gradient stands in
            // so the shape of the screen is the same either way.
            ZStack {
                LinearGradient(
                    colors: [ModuleHue.habits.top.opacity(0.85),
                             ModuleHue.recovery.top.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(LifeOSType.numeral(52, weight: .regular))
                    Text("Add a photo")
                        .font(LifeOSType.secondary.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: -size.height * 0.18)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Content on the frost

    private var content: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(name)
                    .font(LifeOSType.display)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            // The reference's pill-and-circle pair: one bright action, one
            // glass companion. Editing is the thing people come here to do;
            // settings is the place they go from here.
            HStack(spacing: 12) {
                Button { isEditing = true } label: {
                    Text("Edit profile")
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            if !stats.isEmpty { statRow }

            if !highlights.isEmpty { statsPanel("TODAY", items: highlights) }
            if !allTime.isEmpty { statsPanel("ALL TIME", items: allTime) }
        }
    }

    /// A glass grid of figures, the way the reference keeps a rounded panel
    /// under its numbers. Real glass: the photo refracts through it.
    private func statsPanel(_ title: String, items: [ProfileStat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(LifeOSType.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.65))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 14
            ) {
                ForEach(items) { stat in
                    VStack(spacing: 2) {
                        Text(stat.value)
                            .font(LifeOSType.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(stat.label)
                            .font(LifeOSType.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Circular glass controls in the corners, the way the reference does it.
    /// A bar button would need a bar, and a bar would cut the photo off.
    private var topControls: some View {
        HStack {
            // A back chevron on solid white, like the reference's brightest
            // control: this is the one thing on the photo that must always
            // be findable, whatever the picture behind it is doing.
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(LifeOSType.label.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white))
            }
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
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
                VStack(spacing: 3) {
                    Text(stat.value)
                        .font(LifeOSType.numeral)
                        .foregroundStyle(.white)
                    Text(stat.label)
                        .font(LifeOSType.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
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
