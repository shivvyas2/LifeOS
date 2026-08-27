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
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            ZStack {
                                if let draftPhoto, let image = UIImage(data: draftPhoto) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Circle().fill(LifeOSTokens.cardSurface.resolve(scheme))
                                    Image(systemName: "camera.fill")
                                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                }
                            }
                            .frame(width: 104, height: 104)
                            .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    if draftPhoto != nil {
                        Button("Remove photo", role: .destructive) { draftPhoto = nil }
                    }
                }

                Section("Name") {
                    TextField("First name", text: $draft.firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $draft.lastName)
                        .textContentType(.familyName)
                }

                Section("About") {
                    DatePicker(
                        "Birthday",
                        selection: Binding(
                            get: { draft.birthDate ?? Self.defaultBirthday },
                            set: { draft.birthDate = $0 }
                        ),
                        in: Self.earliest...Date.now,
                        displayedComponents: .date
                    )

                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", text: Binding(
                            get: { draft.heightCM.map { String(Int($0.rounded())) } ?? "" },
                            set: { draft.heightCM = Double($0.filter(\.isNumber)) }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        Text("cm").foregroundStyle(.secondary)
                    }

                    Picker("Gender", selection: Binding(
                        get: { Gender(rawValue: draft.gender ?? "") ?? .unspecified },
                        set: { draft.gender = $0.stored }
                    )) {
                        ForEach(Gender.allCases) { Text($0.title).tag($0) }
                    }
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

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Local first: this is what the app renders, so the change lands even
        // if the network does not.
        onSave(draft, draftPhoto)
        dismiss()

        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey,
              let session = KeychainAuthSessionStore().load() else { return }

        try? await SupabaseAuth(baseURL: url, anonKey: key).updateProfile(
            accessToken: session.accessToken,
            firstName: draft.firstName.trimmingCharacters(in: .whitespaces),
            lastName: draft.lastName.trimmingCharacters(in: .whitespaces),
            country: draft.country,
            birthDate: draft.birthDate,
            heightCM: draft.heightCM,
            gender: draft.gender
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
        draftPhoto = UIGraphicsImageRenderer(size: size).image { _ in
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
