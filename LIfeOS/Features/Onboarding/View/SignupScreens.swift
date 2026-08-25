import SwiftUI
import DesignSystem
import Integrations

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
    @Bindable var model: OnboardingViewModel
    var onSkipAuth: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var showCountries = false

    var body: some View {
        SignupScaffold(
            title: "Create your account",
            subtitle: model.identitySubtitle,
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: Space.x2) {
                Picker("", selection: Binding(
                    get: { model.draft.channel },
                    set: { model.switchChannel(to: $0) }
                )) {
                    Text("Phone").tag(SupabaseAuthChannel.phone)
                    Text("Email").tag(SupabaseAuthChannel.email)
                }
                .pickerStyle(.segmented)

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
                            .font(.system(size: 17))
                            .padding(.horizontal, Space.x2)
                            .frame(height: Space.x6 + Space.half)
                            .background(field)
                    }
                } else {
                    TextField("you@example.com", text: $model.draft.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 17))
                        .padding(.horizontal, Space.x2)
                        .frame(height: Space.x6 + Space.half)
                        .background(field)
                }

                if let error = model.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }
                if let note = model.phoneUnavailableNote {
                    Text(note).font(.system(size: 13)).foregroundStyle(.orange)
                }
                if !model.isConfigured {
                    Text("Sign-in isn't configured yet. SUPABASE_ANON_KEY is missing.")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }
            }
        } action: {
            VStack(spacing: Space.half) {
                PrimaryButton(model.sendButtonTitle, isLoading: model.isBusy) {
                    Task { await model.sendCode() }
                }
                .disabled(!model.draft.canSendCode || !model.isConfigured)

                if let onSkipAuth {
                    SecondaryButton("Continue without an account") { onSkipAuth() }
                }
            }
        }
        .task { await model.loadChannels() }
        .sheet(isPresented: $showCountries) {
            CountryPicker(
                selection: $model.draft.country,
                dial: $model.draft.dialCode,
                allowedIDs: DialCountries.otpRegions
            )
        }
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(LifeOSTokens.cardSurface.resolve(scheme))
    }
}

/// Step 2. Six digits.
struct CodeScreen: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        SignupScaffold(
            title: "Enter your code",
            subtitle: "Sent to \(model.destinationLabel).",
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: Space.x2) {
                TextField("000000", text: $model.draft.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .tracking(8)
                    .multilineTextAlignment(.center)
                    .frame(height: Space.x8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    )
                    .focused($focused)

                if let error = model.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }

                Button(model.resendIn > 0 ? "Resend in \(model.resendIn)s" : "Resend code") {
                    Task { await model.sendCode() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LifeOSTokens.accent)
                .disabled(model.resendIn > 0)
            }
            .onAppear { focused = true }
        } action: {
            PrimaryButton("Verify", isLoading: model.isBusy) {
                Task { await model.verifyCode() }
            }
            .disabled(!model.draft.canVerify)
        }
    }
}

/// Step 3. Name and country.
struct ProfileScreen: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showCountries = false

    var body: some View {
        SignupScaffold(
            title: "About you",
            subtitle: "Only used to personalise the app.",
            onBack: { model.back() }
        ) {
            VStack(spacing: Space.x2) {
                TextField("First name", text: $model.draft.firstName)
                    .textContentType(.givenName)
                    .modifier(FieldStyle(scheme: scheme))
                TextField("Last name", text: $model.draft.lastName)
                    .textContentType(.familyName)
                    .modifier(FieldStyle(scheme: scheme))

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

/// Shown after a magic link is sent. There is nothing to type, so the screen's
/// only job is to say what happens next and offer a way out if it does not.
struct LinkSentScreen: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SignupScaffold(
            title: "Check your email",
            subtitle: "We sent a sign-in link to \(model.destinationLabel). Open it on this device and you'll come straight back here.",
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack(spacing: Space.x2) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 20))
                        .frame(width: Space.x6, height: Space.x6)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .fill(LifeOSTokens.canvas.resolve(scheme))
                        )
                        .foregroundStyle(LifeOSTokens.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for you to tap the link")
                            .font(.system(size: 15, weight: .semibold))
                        Text("It expires shortly.")
                            .font(.system(size: 13))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
                .padding(Space.x2)
                .background(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(LifeOSTokens.cardSurface.resolve(scheme))
                )

                if let error = model.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }

                Button(model.resendIn > 0 ? "Resend in \(model.resendIn)s" : "Send another link") {
                    Task { await model.sendCode() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LifeOSTokens.accent)
                .disabled(model.resendIn > 0)
            }
        } action: {
            SecondaryButton("Use a different address") { model.back() }
        }
    }
}
