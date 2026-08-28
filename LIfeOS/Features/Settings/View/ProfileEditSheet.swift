import SwiftUI
import PhotosUI
import DesignSystem
import Integrations

/// Changing the profile after signup.
///
/// Signup asks for these once and then never again, which is fine for a name
/// and wrong for a photo: the picture is the thing people revisit. This is the
/// same set of fields, reachable from the profile at any time.
///
/// It saves locally first and pushes to the server after. That order is
/// deliberate: the local copy is what the app displays, so writing it first
/// means the change is visible immediately and survives a failed request. A
/// signed-out user gets the local change and nothing else, which is the
/// correct outcome rather than an error about an account they do not have.
struct ProfileEditSheet: View {
    let profile: LocalProfile
    let photo: Data?
    let onSave: (LocalProfile, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: LocalProfile
    @State private var draftPhoto: Data?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isSaving = false

    init(profile: LocalProfile, photo: Data?, onSave: @escaping (LocalProfile, Data?) -> Void) {
        self.profile = profile
        self.photo = photo
        self.onSave = onSave
        _draft = State(initialValue: profile)
        _draftPhoto = State(initialValue: photo)
    }

    var body: some View {
        NavigationStack {
            GradientCanvas(hue: .habits) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        photoPicker
                            .frame(maxWidth: .infinity)

                        sectionLabel("Name")
                        GlassPanel {
                            VStack(spacing: 0) {
                                TextField("First name", text: $draft.firstName)
                                    .textContentType(.givenName)
                                    .font(LifeOSType.secondary)
                                    .padding(.vertical, 10)
                                divider
                                TextField("Last name", text: $draft.lastName)
                                    .textContentType(.familyName)
                                    .font(LifeOSType.secondary)
                                    .padding(.vertical, 10)
                            }
                        }

                        sectionLabel("About")
                        GlassPanel {
                            VStack(spacing: 0) {
                                DatePicker(
                                    "Birthday",
                                    selection: Binding(
                                        get: { draft.birthDate ?? Self.defaultBirthday },
                                        set: { draft.birthDate = $0 }
                                    ),
                                    in: Self.earliest...Date.now,
                                    displayedComponents: .date
                                )
                                .font(LifeOSType.secondary.weight(.medium))
                                .padding(.vertical, 6)

                                divider

                                HStack {
                                    Text("Height")
                                        .font(LifeOSType.secondary.weight(.medium))
                                    Spacer()
                                    TextField("—", text: Binding(
                                        get: { draft.heightCM.map { String(Int($0.rounded())) } ?? "" },
                                        set: { draft.heightCM = Double($0.filter(\.isNumber)) }
                                    ))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                    Text("cm")
                                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                }
                                .padding(.vertical, 10)

                                divider

                                HStack {
                                    Text("Gender")
                                        .font(LifeOSType.secondary.weight(.medium))
                                    Spacer()
                                    Picker("Gender", selection: Binding(
                                        get: { Gender(rawValue: draft.gender ?? "") ?? .unspecified },
                                        set: { draft.gender = $0.stored }
                                    )) {
                                        ForEach(Gender.allCases) { Text($0.title).tag($0) }
                                    }
                                    .labelsHidden()
                                    .tint(LifeOSTokens.primaryText.resolve(scheme))
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    // Capped and centred rather than filling the pane. An
                    // iPad form sheet is wide enough that full-width rows put
                    // a label and its value at opposite ends of the screen.
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onChange(of: pickedPhoto) { _, item in Task { await load(item) } }
        }
    }

    /// The photo is the reason this sheet exists: a big circle with a camera
    /// badge, and the remove affordance kept small beneath it.
    private var photoPicker: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let draftPhoto, let image = UIImage(data: draftPhoto) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            ZStack {
                                Circle().fill(LifeOSTokens.cardSurface.resolve(scheme))
                                Image(systemName: "person.fill")
                                    .font(LifeOSType.numeral(44, weight: .bold))
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            }
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())

                    Image(systemName: "camera.fill")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(LifeOSTokens.accent))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change photo")
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(LifeOSType.label.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
    }

    private var divider: some View {
        Rectangle()
            .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.08))
            .frame(height: 1)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Local first: this is what the app renders, so the change lands even
        // if the network does not.
        onSave(draft, draftPhoto)
        dismiss()

        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey,
              let session = KeychainAuthSessionStore().load() else { return }

        let profiles = ProfileClient(baseURL: url, anonKey: key)
        var profile = RemoteProfile(
            firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
            lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
            country: draft.country,
            birthDate: draft.birthDate,
            heightCM: draft.heightCM,
            gender: draft.gender
        )

        // The picture goes first, so the row never points at an object that
        // does not exist. Removing one is a delete rather than a null: leaving
        // the object behind would keep serving a face the person took down.
        if let photo = draftPhoto {
            profile.avatarPath = try? await profiles.uploadAvatar(
                photo, userID: session.userID, accessToken: session.accessToken
            )
        } else {
            try? await profiles.deleteAvatar(
                userID: session.userID, accessToken: session.accessToken
            )
        }

        try? await profiles.save(
            profile, userID: session.userID, accessToken: session.accessToken
        )
    }

    /// Downsized before it is kept, the same as at signup: this is displayed
    /// at 104 points and a camera-roll original is several megabytes.
    private func load(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        let side: CGFloat = 512
        let scale = min(side / image.size.width, side / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Scale 1, because the renderer otherwise draws at the device's scale
        // and a 512 point box becomes a 1536 pixel bitmap on a 3x phone. Nine
        // times the pixels asked for, which undoes most of the downsizing.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        draftPhoto = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.8)
    }

    private static var defaultBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    }

    private static var earliest: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
    }
}
