import SwiftUI
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
    var onBack: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()

            VStack(alignment: .leading, spacing: Space.x4) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: Space.x5, height: Space.x5)
                            .background(Circle().fill(LifeOSTokens.cardSurface.resolve(scheme)))
                    }
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                }

                VStack(alignment: .leading, spacing: Space.x1) {
                    StaggeredAppear(index: 0) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    StaggeredAppear(index: 1) {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                StaggeredAppear(index: 2) { content }

                Spacer(minLength: Space.x3)

                action
            }
            .padding(.horizontal, Space.x3)
            .padding(.top, Space.x2)
            .padding(.bottom, Space.x4)
        }
    }
}

/// Step 1. Phone first, email as the alternative, because a phone number is
/// the identity most people can recall and keep.
struct IdentityScreen: View {
    /// Which field owns the keyboard. Drives the focus ring: before this the
    /// screen gave no visual answer to "where am I typing".
    private enum Field { case phone, email }

    @Bindable var model: OnboardingViewModel
    var onSkipAuth: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var showCountries = false
    @FocusState private var focus: Field?

    var body: some View {
        SignupScaffold(
            title: model.identityTitle,
            subtitle: model.identitySubtitle,
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: Space.x2) {
                SegmentedPills(
                    selection: Binding(
                        get: { model.draft.channel },
                        set: { model.switchChannel(to: $0) }
                    ),
                    options: [(.email, "Email"), (.phone, "Phone")]
                )

                if model.draft.channel == .phone {
                    HStack(spacing: Space.x1) {
                        Button { showCountries = true } label: {
                            HStack(spacing: Space.half) {
                                Text(model.draft.dialCode)
                                    .font(.system(size: 17, weight: .medium))
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
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
                    TextField("you@example.com", text: $model.draft.email)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.accent)
                        .frame(height: Space.x5)
                }
            }
        } action: {
            VStack(spacing: Space.half) {
                PrimaryButton("Send code", isLoading: model.isBusy) {
                    Task { await model.sendCode() }
                }
                .disabled(!model.draft.canSendCode || !model.isConfigured)

                Button(model.modeSwitchTitle) { model.toggleMode() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(height: Space.x5)

                if let onSkipAuth {
                    SecondaryButton("Continue without an account") { onSkipAuth() }
                }
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
                .font(.system(size: 14, weight: .medium))
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
            PrimaryButton("Verify", isLoading: model.isBusy) {
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
struct ProfileScreen: View {
    private enum Field { case first, last }

    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showCountries = false
    @FocusState private var focus: Field?

    var body: some View {
        SignupScaffold(
            title: "About you",
            subtitle: "Only used to personalise the app.",
            onBack: { model.back() }
        ) {
            VStack(spacing: Space.x2) {
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

                Button { showCountries = true } label: {
                    HStack {
                        Text(countryName)
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    .font(.system(size: 17))
                    .padding(.horizontal, Space.x2)
                    .frame(height: Space.x6 + Space.half)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    )
                }
            }
        } action: {
            PrimaryButton("Continue", isLoading: model.isBusy) {
                Task { await model.saveProfile() }
            }
            .disabled(!model.draft.canFinishProfile)
        }
        .sheet(isPresented: $showCountries) {
            CountryPicker(selection: $model.draft.country, dial: $model.draft.dialCode)
        }
    }

    private var countryName: String {
        Locale.current.localizedString(forRegionCode: model.draft.country) ?? model.draft.country
    }
}

private struct FieldStyle: ViewModifier {
    let scheme: ColorScheme
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17))
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
