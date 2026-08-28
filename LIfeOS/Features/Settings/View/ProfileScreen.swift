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
///
/// # Two shapes, not one stretched
///
/// A phone gets exactly that: one column standing on the frost. A wide pane
/// gets the same parts rearranged rather than resized. The sharp photo becomes
/// a card at the aspect the camera shot instead of a bleed, and in landscape it
/// stands in its own column beside the figures. Stretching the phone layout
/// across 1366 points gave a thousand-point-wide "Edit profile" capsule and a
/// 3:4 photograph taller than the iPad it was on; neither is a design.
struct ProfileScreen: View {
    @Bindable var settings: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    var fitbit: FitbitConnectionViewModel?
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
    /// The screen asks the design system how wide the pane is rather than the
    /// platform, for the reason `LayoutMetrics` exists: the size class is read
    /// once, in the shell, and everything below works in our own terms.
    @Environment(\.layout) private var layout
    @State private var photo: Data? = ProfilePhotoStore.load()
    @State private var profile: LocalProfile = ProfileStore.load()
    @State private var isEditing = false
    @State private var showSettings = false
    @State private var showFriends = false

    private var name: String {
        profile.fullName.isEmpty ? "Your profile" : profile.fullName
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    backdrop(size: geo.size)

                    if layout.isRegular {
                        wideBody(geo: geo)
                    } else {
                        content
                            .padding(.horizontal, 24)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 56)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(alignment: .topLeading) { topControls(geo: geo) }
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) {
                SettingsScreen(
                    model: settings, whoop: whoop, fitbit: fitbit, health: health, plaid: plaid,
                    onSignOut: onSignOut
                )
            }
            .navigationDestination(isPresented: $showFriends) {
                FriendsScreen()
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

    /// The blurred copy of the photo, full bleed, under everything.
    ///
    /// On a phone the sharp copy sits on top of it as a 3:4 block anchored to
    /// the top, and the two read as one image. A phone is about 9:19.5, so
    /// filling it with a 3:4 photograph crops away most of the frame from the
    /// centre outwards, which is exactly where faces are: portraits came out
    /// beheaded. Three by four is what the camera shot.
    ///
    /// A wide pane gets no sharp block here at all. Sized off an iPad's width
    /// that block is 1821 points tall in landscape — taller than the screen —
    /// and sized off the height instead it would crop a portrait from the sides
    /// and take the face with it. The sharp photo moves into `photoCard`.
    @ViewBuilder
    private func backdrop(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            // Behind everything, so the frost still reaches the bottom of the
            // screen once the sharp block has ended. Blurred harder on a wide
            // pane because far more of it is visible there.
            photoLayer(size: size)
                .blur(radius: layout.isRegular ? 64 : 38, opaque: true)

            if !layout.isRegular {
                photoLayer(size: CGSize(width: size.width, height: size.width * 4 / 3))
                    .frame(height: size.width * 4 / 3, alignment: .top)
                    // Fades into the frost rather than ending on a hard line,
                    // which is what keeps the two copies reading as one image.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.72),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            // A phone darkens toward the bottom, where all the type is. A wide
            // pane carries type across its whole height, so the wash is even.
            LinearGradient(
                stops: layout.isRegular
                    ? [.init(color: .black.opacity(0.34), location: 0.0),
                       .init(color: .black.opacity(0.46), location: 1.0)]
                    : [.init(color: .clear, location: 0.45),
                       .init(color: .black.opacity(0.38), location: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func photoLayer(size: CGSize) -> some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                // Anchored to the top, not centred. `scaledToFill` overflows
                // by design and a centred crop trims equally from both ends,
                // taking the head off a portrait. Biasing upward keeps the
                // part of a photograph anyone actually framed.
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
        } else {
            // No photo is a state, not a gap: the module gradient stands in
            // so the shape of the screen is the same either way.
            placeholderArt(iconSize: 52, offset: -size.height * 0.18)
                .frame(width: size.width, height: size.height)
        }
    }

    private func placeholderArt(iconSize: CGFloat, offset: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [ModuleHue.habits.top.opacity(0.85),
                         ModuleHue.recovery.top.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(LifeOSType.numeral(iconSize, weight: .regular))
                Text("Add a photo")
                    .font(LifeOSType.secondary.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .offset(y: offset)
        }
    }

    /// The photograph at its own aspect on a wide pane: a rounded 3:4 card
    /// standing on the frost rather than bleeding to the edges. A card the
    /// shape the camera shot keeps the frame someone actually composed, and it
    /// gives the wide layout an object to build a column around.
    private func photoCard(width: CGFloat) -> some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderArt(iconSize: 46, offset: 0)
            }
        }
        .frame(width: width, height: width * 4 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 28, y: 16)
        .onTapGesture { isEditing = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Change photo")
    }

    // MARK: - Wide panes

    /// Landscape splits the screen in two: who this is on the left, what they
    /// have done on the right. Portrait keeps one column, capped and centred,
    /// because a 1024-point column is already about as wide as text wants to
    /// be and splitting it would leave two thin ones.
    ///
    /// The split also needs something to put in the second column. With no
    /// figures to show it collapses back to one, rather than standing the
    /// photo off-centre beside a void.
    @ViewBuilder
    private func wideBody(geo: GeometryProxy) -> some View {
        let top = topSafe(geo) + 66
        let bottom = geo.safeAreaInsets.bottom + 28

        if geo.size.width >= geo.size.height, hasFigures {
            let card = cardWidth(geo: geo, top: top, bottom: bottom)

            // One scroll view around both columns rather than one inside the
            // right column. A `ScrollView` is greedy vertically, so a nested
            // one filled the pane and pinned the photo to the top however
            // little there was to show; `minHeight` on the row lets the pair
            // centre when it fits and scroll when it does not.
            ScrollView {
                // Centred against each other rather than top-aligned. The
                // two columns are rarely the same length — a fresh account has
                // three figures and a full one has a dozen — and hanging both
                // from the top left whichever is shorter with a void under it.
                HStack(alignment: .center, spacing: 44) {
                    identityColumn(cardWidth: card)
                        .frame(width: card)
                    figures
                        .frame(maxWidth: Self.figuresColumnWidth)
                }
                .frame(maxWidth: card + 44 + Self.figuresColumnWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.top, top)
                .padding(.bottom, bottom)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        } else {
            ScrollView {
                VStack(spacing: 30) {
                    identityColumn(cardWidth: min(400, geo.size.width * 0.42))
                    if hasFigures { figures }
                }
                .frame(maxWidth: Self.singleColumnWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.top, top)
                .padding(.bottom, bottom)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The photo card, sized so the whole identity column fits the pane
    /// without scrolling. Height leads: a 3:4 card is the tallest thing here,
    /// and `nameBlock` plus `actions` under it need roughly 190 points.
    private func cardWidth(geo: GeometryProxy, top: CGFloat, bottom: CGFloat) -> CGFloat {
        let vertical = geo.size.height - top - bottom - 190
        return max(232, min(460, min(geo.size.width * 0.34, vertical * 3 / 4)))
    }

    private func identityColumn(cardWidth: CGFloat) -> some View {
        VStack(spacing: 22) {
            photoCard(width: cardWidth)
            nameBlock
            actions
        }
    }

    private var figures: some View {
        VStack(spacing: 20) {
            if !stats.isEmpty { statRow }
            if !highlights.isEmpty { statsPanel("TODAY", items: highlights) }
            if !allTime.isEmpty { statsPanel("ALL TIME", items: allTime) }
        }
    }

    private var hasFigures: Bool {
        !stats.isEmpty || !highlights.isEmpty || !allTime.isEmpty
    }

    /// Wide enough for three figures across with room to breathe, narrow
    /// enough that a 1366-point pane does not spread six numbers over a metre.
    private static let figuresColumnWidth: CGFloat = 520
    private static let singleColumnWidth: CGFloat = 620

    // MARK: - Content on the frost

    private var content: some View {
        VStack(spacing: 20) {
            nameBlock
            actions
            if hasFigures { figures }
        }
    }

    private var nameBlock: some View {
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
    }

    /// The reference's pill-and-circle pair: one bright action, one glass
    /// companion. Editing is the thing people come here to do; settings is the
    /// place they go from here.
    private var actions: some View {
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

            // Labelled, not a bare glyph. Two people in a circle is the icon
            // every app uses for something different, and this was the only
            // door to friends in the whole app: nobody found it, which is a
            // feature that may as well not exist.
            Button { showFriends = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.2.fill")
                    Text("Friends")
                }
                .font(LifeOSType.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .glassEffect(.regular.interactive())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Friends")

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
    ///
    /// The phone keeps its hand-set 60 points, which is what a notch plus a
    /// comfortable gap comes to. A pane cannot: an iPad's top inset is 24 and
    /// a Stage Manager window's is zero, so the number is measured there.
    private func topControls(geo: GeometryProxy) -> some View {
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
        .padding(.horizontal, layout.isRegular ? layout.gutter : 20)
        .padding(.top, layout.isRegular ? topSafe(geo) + 10 : 60)
    }

    /// A floor under the measured inset, so a window with no inset at all does
    /// not put the back button against the very top edge.
    private func topSafe(_ geo: GeometryProxy) -> CGFloat {
        max(geo.safeAreaInsets.top, 18)
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
