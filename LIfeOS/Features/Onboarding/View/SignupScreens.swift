import SwiftUI
import PhotosUI
import OSLog
import DesignSystem
import Integrations

private let signupLog = Logger(subsystem: "com.shivvyas.lifeos", category: "signup")

/// Shared chrome for every signup step: neutral canvas, back affordance,
/// title block, content, and one primary action pinned to the bottom.
/// Having it in one place is what keeps the four steps visually identical.
struct SignupScaffold<Content: View, Action: View>: View {
    let title: String
    let subtitle: String
    var step = 1
    var totalSteps = 3
    var showsProgress = true
    var onBack: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x4) {
                HStack {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Back")
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: LifeOSMark.symbol)
                            .foregroundStyle(LifeOSTokens.accent)
                        Text("LifeOS").font(.title3.bold())
                    }
                    .accessibilityElement(children: .combine)
                }

                VStack(alignment: .leading, spacing: Space.x2) {
                    if showsProgress {
                        Text("YOUR ACCOUNT · \(step) OF \(totalSteps)")
                            .font(.caption.weight(.medium))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(1...totalSteps, id: \.self) { index in
                                Rectangle()
                                    .fill(index <= step ? LifeOSTokens.accent : LifeOSTokens.dotMissed.resolve(scheme))
                                    .frame(height: 3)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.largeTitle.bold())
                        .tracking(-0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Space.x2)
                    Text(subtitle)
                        .font(LifeOSType.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x2)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            action
                .padding(.horizontal, Space.x4)
                .padding(.vertical, Space.x2)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(LifeOSTokens.canvas.resolve(scheme))
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .tint(LifeOSTokens.accent)
    }
}

struct OnboardingActionButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body.weight(.semibold))
                Spacer()
                if isLoading { ProgressView().tint(LifeOSTokens.accent) }
                else { Image(systemName: "arrow.right").foregroundStyle(LifeOSTokens.accent) }
            }
            .padding(.horizontal, Space.x3)
            .frame(minHeight: 56)
            .foregroundStyle(LifeOSTokens.canvas.resolve(scheme))
            .background(LifeOSTokens.primaryText.resolve(scheme),
                        in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? 1 : 0.4)
        }
        .disabled(isLoading)
    }
}

/// Step 1. Phone first, email as the alternative, because a phone number is
/// the identity most people can recall and keep.
struct IdentityScreen: View {
    /// Which field owns the keyboard. Drives the focus ring: before this the
    /// screen gave no visual answer to "where am I typing".
    private enum Field { case phone, email }

    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showCountries = false
    @FocusState private var focus: Field?

    var body: some View {
        SignupScaffold(
            title: model.identityTitle,
            subtitle: model.identitySubtitle,
            totalSteps: model.mode == .signIn ? 2 : 3,
            showsProgress: model.mode == .signUp,
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack(spacing: Space.x3) {
                    ForEach([SupabaseAuthChannel.email, .phone], id: \.self) { channel in
                        Button { model.switchChannel(to: channel) } label: {
                            VStack(spacing: 10) {
                                Text(channel == .email ? "Email" : "Phone")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                Rectangle()
                                    .fill(model.draft.channel == channel ? LifeOSTokens.accent : .clear)
                                    .frame(height: 2)
                            }
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(model.draft.channel == channel
                            ? LifeOSTokens.primaryText.resolve(scheme)
                            : LifeOSTokens.secondaryText.resolve(scheme))
                        .accessibilityAddTraits(model.draft.channel == channel ? .isSelected : [])
                    }
                }

                Text(model.draft.channel == .email ? "EMAIL ADDRESS" : "PHONE NUMBER")
                    .font(.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                if model.draft.channel == .phone {
                    HStack(spacing: Space.x1) {
                        Button { showCountries = true } label: {
                            HStack(spacing: Space.half) {
                                Text(model.draft.dialCode)
                                    .font(LifeOSType.body.weight(.medium))
                                Image(systemName: "chevron.down").font(LifeOSType.eyebrow.weight(.bold))
                            }
                            .frame(height: Space.x6 + Space.half)
                            .padding(.horizontal, Space.x2)
                            .background(field)
                        }
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                        TextField("Phone number", text: $model.draft.phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .autocorrectionDisabled()
                            .writingToolsBehavior(.disabled)
                            .focused($focus, equals: .phone)
                            .submitLabel(.continue)
                            .onSubmit(send)
                            .focusableField(isFocused: focus == .phone)
                    }
                } else {
                    TextField("Email address", text: $model.draft.email,
                              prompt: Text(verbatim: "you@example.com").foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme)))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .writingToolsBehavior(.disabled)
                        .focused($focus, equals: .email)
                        .submitLabel(.continue)
                        .onSubmit(send)
                        .focusableField(isFocused: focus == .email)
                }

                // One complaint at a time. Three stacked coloured lines read as
                // a broken app rather than as one thing to fix.
                if let status = InlineStatus.resolve(
                    error: model.errorMessage,
                    configuration: model.isConfigured ? nil : Self.unavailableCopy,
                    warning: model.phoneUnavailableNote
                ) {
                    InlineStatusView(status)
                }

                // Kept below the status rather than folded into it: this is an
                // action the user can take, not another thing going wrong.
                if model.phoneSendFailed {
                    Button("Use email instead") { model.useEmailInstead() }
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.accent)
                        .frame(height: Space.x5)
                }
            }
        } action: {
            VStack(spacing: Space.half) {
                OnboardingActionButton("Send code", isLoading: model.isBusy) {
                    Task { await model.sendCode() }
                }
                .disabled(!model.draft.canSendCode || !model.isConfigured)

                Button(model.modeSwitchTitle) { model.toggleMode() }
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(height: Space.x5)

            }
        }
        .task {
            await model.loadChannels()
            // The key name is a fact for whoever reads the log, not for whoever
            // is trying to sign in.
            if !model.isConfigured {
                signupLog.error("sign-in unavailable: SUPABASE_ANON_KEY is missing")
            }
        }
        .sheet(isPresented: $showCountries) {
            CountryPicker(
                selection: $model.draft.country,
                dial: $model.draft.dialCode,
                allowedIDs: DialCountries.otpRegions
            )
        }
    }

    /// What a user can act on. The missing key goes to the log instead.
    private static let unavailableCopy = "Sign-in is unavailable right now. Please try again in a moment."

    private var field: some View {
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(LifeOSTokens.cardSurface.resolve(scheme))
    }

    /// Return on the keyboard does what the button does, when the button would
    /// have been enabled.
    private func send() {
        guard model.draft.canSendCode, model.isConfigured else { return }
        Task { await model.sendCode() }
    }
}

/// Step 2. Six digits.
///
/// This is the screen people fail on, so it does the work instead of asking for
/// it: six boxes rather than one tracked field, verification fired the moment
/// the sixth digit lands, and a wrong code that shakes and buzzes rather than
/// quietly turning a line of text red.
struct CodeScreen: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    /// Bumped on every new error, which is what drives the shake and the
    /// haptic. A counter rather than a Bool: two bad codes in a row must play
    /// twice, and a Bool that is already `true` animates nothing.
    @State private var wrongAttempts = 0

    var body: some View {
        SignupScaffold(
            title: "Enter your code",
            subtitle: "Sent to \(model.destinationLabel).",
            step: 2,
            totalSteps: model.mode == .signIn ? 2 : 3,
            showsProgress: model.mode == .signUp,
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: Space.x2) {
                CodeField(text: $model.draft.code, count: 6) {
                    verify()
                }
                .shake(wrongAttempts)
                .animation(.spring(response: 0.28, dampingFraction: 0.4), value: wrongAttempts)

                if let status = InlineStatus.resolve(
                    error: model.errorMessage,
                    configuration: nil,
                    warning: nil
                ) {
                    InlineStatusView(status)
                }

                Button(model.resendIn > 0 ? "Resend in \(model.resendIn)s" : "Resend code") {
                    Task { await model.sendCode() }
                }
                .font(LifeOSType.label)
                .foregroundStyle(LifeOSTokens.accent)
                .disabled(model.resendIn > 0)
            }
            .onChange(of: model.errorMessage) { _, new in
                guard new?.isEmpty == false else { return }
                wrongAttempts += 1
            }
            .sensoryFeedback(.error, trigger: wrongAttempts)
        } action: {
            // Kept even though the sixth digit auto-verifies: autofill can land
            // a full code without a keystroke, and a screen with no button
            // leaves that user nothing to press.
            OnboardingActionButton("Verify", isLoading: model.isBusy) {
                verify()
            }
            .disabled(!model.draft.canVerify)
        }
    }

    private func verify() {
        guard model.draft.canVerify, !model.isBusy else { return }
        Task { await model.verifyCode() }
    }
}

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

struct CountryPicker: View {
    @Binding var selection: String
    @Binding var dial: String
    var allowedIDs: Set<String>? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [DialCountry] {
        let all = DialCountries.all.filter { allowedIDs?.contains($0.id) ?? true }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.dial.contains(search) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { country in
                Button {
                    selection = country.id
                    dial = country.dial
                    dismiss()
                } label: {
                    HStack(spacing: Space.x2) {
                        Text(country.flag)
                        Text(country.name)
                        Spacer()
                        Text(country.dial).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .searchable(text: $search)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
