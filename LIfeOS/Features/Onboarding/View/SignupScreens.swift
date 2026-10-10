import SwiftUI
import PhotosUI
import OSLog
import DesignSystem
import Integrations
import AccountUI

private let signupLog = Logger(subsystem: "com.shivvyas.lifeos", category: "signup")

/// Step 3. Name and country.
struct ProfileStepScreen: View {
    private enum Field { case first, last, height }

    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showCountries = false
    @State private var pickedPhoto: PhotosPickerItem?
    @FocusState private var focus: Field?

    /// Imperial where the region expects it. Someone who thinks in feet and
    /// inches should not have to convert their own height to fill this in.
    @State private var usesImperial = Locale.current.measurementSystem != .metric

    var body: some View {
        SignupScaffold(
            title: "About you",
            subtitle: "A name makes this your space. Everything else is optional.",
            step: 3,
            onBack: { model.back() }
        ) {
            VStack(spacing: Space.x2) {
                avatarPicker

                TextField("First name", text: $model.draft.firstName)
                    .textContentType(.givenName)
                    .focused($focus, equals: .first)
                    .submitLabel(.next)
                    .onSubmit { focus = .last }
                    .focusableField(isFocused: focus == .first)
                TextField("Last name", text: $model.draft.lastName)
                    .textContentType(.familyName)
                    .focused($focus, equals: .last)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .focusableField(isFocused: focus == .last)

                birthdayRow
                heightRow
                genderRow
                countryRow
            }
        } action: {
            OnboardingActionButton("Continue", isLoading: model.isBusy) {
                Task { await model.saveProfile() }
            }
            .disabled(!model.draft.canFinishProfile)
        }
        .sheet(isPresented: $showCountries) {
            CountryPicker(selection: $model.draft.country, dial: $model.draft.dialCode)
        }
        .onChange(of: pickedPhoto) { _, item in
            Task { await load(item) }
        }
    }

    // MARK: - Photo

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickedPhoto, matching: .images) {
            ZStack {
                if let data = model.draft.photo, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(LifeOSTokens.cardSurface.resolve(scheme))
                    Image(systemName: "camera.fill")
                        .font(LifeOSType.body)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if model.draft.photo != nil {
                    Image(systemName: "pencil.circle.fill")
                        .font(LifeOSType.body)
                        .foregroundStyle(LifeOSTokens.accent)
                        .background(Circle().fill(LifeOSTokens.canvas.resolve(scheme)))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.draft.photo == nil ? "Add a photo" : "Change photo")
        .padding(.bottom, Space.half)
    }

    /// Downsized before it is kept. A full-resolution camera roll image is
    /// several megabytes, and this is displayed at 96 points.
    private func load(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        model.draft.photo = ProfilePhotoDownsizing.jpeg(from: image)
    }

    // MARK: - Rows

    private var birthdayRow: some View {
        row(label: "Birthday", value: nil) {
            DatePicker(
                "",
                selection: Binding(
                    get: { model.draft.birthDate ?? Self.defaultBirthday },
                    set: { model.draft.birthDate = $0 }
                ),
                in: Self.earliestBirthday...Date.now,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
    }

    private var heightRow: some View {
        row(label: "Height", value: nil) {
            if usesImperial {
                HStack(spacing: Space.half) {
                    TextField("ft", text: feetText)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                    Text("ft").font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    TextField("in", text: inchesText)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                    Text("in").font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
                .focused($focus, equals: .height)
            } else {
                HStack(spacing: Space.half) {
                    TextField("cm", text: centimetreText)
                        .keyboardType(.numberPad)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .height)
                    Text("cm").font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
    }

    private var genderRow: some View {
        row(label: "Gender", value: nil) {
            Picker("", selection: $model.draft.gender) {
                ForEach(Gender.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .tint(LifeOSTokens.primaryText.resolve(scheme))
        }
    }

    private var countryRow: some View {
        Button { showCountries = true } label: {
            HStack {
                Text(countryName)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(LifeOSType.caption.weight(.bold))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .font(LifeOSType.body)
            .padding(.horizontal, Space.x2)
            .frame(height: Space.x6 + Space.half)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            )
        }
    }

    /// One labelled row, so the optional fields read as a set rather than as
    /// four differently shaped controls.
    private func row(label: String, value: String?, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(LifeOSType.body)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Spacer(minLength: Space.x1)
            control()
            if let value {
                Text(value)
                    .font(LifeOSType.body)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(.horizontal, Space.x2)
        .frame(height: Space.x6 + Space.half)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
    }

    // MARK: - Height bindings

    /// Centimetres are the stored truth; these only translate for display, so
    /// switching units can never round the underlying value away.
    private var centimetreText: Binding<String> {
        Binding(
            get: { model.draft.heightCM.map { String(Int($0.rounded())) } ?? "" },
            set: { model.draft.heightCM = Double($0.filter(\.isNumber)) }
        )
    }

    private var feetText: Binding<String> {
        Binding(
            get: {
                guard let cm = model.draft.heightCM else { return "" }
                return String(Int(cm / 2.54) / 12)
            },
            set: { newValue in
                let feet = Double(newValue.filter(\.isNumber)) ?? 0
                let inches = Double(Int((model.draft.heightCM ?? 0) / 2.54) % 12)
                model.draft.heightCM = (feet * 12 + inches) * 2.54
            }
        )
    }

    private var inchesText: Binding<String> {
        Binding(
            get: {
                guard let cm = model.draft.heightCM else { return "" }
                return String(Int(cm / 2.54) % 12)
            },
            set: { newValue in
                let inches = Double(newValue.filter(\.isNumber)) ?? 0
                let feet = Double(Int((model.draft.heightCM ?? 0) / 2.54) / 12)
                model.draft.heightCM = (feet * 12 + inches) * 2.54
            }
        )
    }

    // MARK: - Values

    private var countryName: String {
        Locale.current.localizedString(forRegionCode: model.draft.country) ?? model.draft.country
    }

    /// Opens on a plausible adult birthday rather than today, so the wheel is
    /// not thirty years of scrolling from a date nobody has.
    private static var defaultBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    }

    private static var earliestBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
    }
}

private struct FieldStyle: ViewModifier {
    let scheme: ColorScheme
    func body(content: Content) -> some View {
        content
            .font(LifeOSType.body)
            .padding(.horizontal, Space.x2)
            .frame(height: Space.x6 + Space.half)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            )
    }
}
