import SwiftUI
import DesignSystem
import Integrations

/// What is waiting on you: requests to answer above conversations to return
/// to, in that order, because a decision someone is waiting on outranks a
/// message you have already read.
///
/// The same vocabulary as `FriendsScreen`, which is where it is reached from:
/// a gradient canvas, eyebrow section headings, initial bubbles coloured by a
/// stable hash of the name. Pushed rather than tabbed, like settings.
struct InboxScreen: View {
    @State private var viewModel = InboxViewModel()
    @Environment(\.colorScheme) private var scheme

    /// `SocialProfile` is not `Hashable`, so a tapped row is held here and
    /// paired with `isPresented:`, the way `FriendsScreen` does it.
    @State private var openChat: SocialProfile?
    @State private var showChat = false

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        GradientCanvas(hue: .recovery) {
            switch viewModel.phase {
            case .guest:
                message("Sign in to see requests and messages.")
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                ready
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.appear() }
        .navigationDestination(isPresented: $showChat) {
            if let openChat {
                FriendChatScreen(friend: openChat)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(LifeOSType.secondary)
            .foregroundStyle(secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var ready: some View {
        if viewModel.requests.isEmpty && viewModel.threads.isEmpty {
            message("Nothing waiting. Requests and messages land here.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(LifeOSType.secondary)
                            .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                    }
                    if !viewModel.requests.isEmpty { requestsSection }
                    if !viewModel.threads.isEmpty { threadsSection }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refresh() }
        }
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("REQUESTS")
            ForEach(viewModel.requests, id: \.friendshipID) { entry in
                HStack(spacing: 12) {
                    InitialBubble(name: entry.profile.displayName)
                    Text(entry.profile.displayName)
                        .font(LifeOSType.secondary.weight(.medium))
                        .foregroundStyle(primary)
                    Spacer(minLength: 8)
                    Button("Decline") {
                        Task { await viewModel.decline(entry.friendshipID) }
                    }
                    .buttonStyle(.plain)
                    .font(LifeOSType.secondary.weight(.medium))
                    .foregroundStyle(secondary)
                    CapsuleButton(title: "Accept") {
                        Task { await viewModel.accept(entry.friendshipID) }
                    }
                }
            }
        }
    }

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("MESSAGES")
            ForEach(viewModel.threads) { thread in
                Button {
                    openChat = thread.friend
                    showChat = true
                } label: {
                    HStack(spacing: 12) {
                        InitialBubble(name: thread.friend.displayName)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(thread.friend.displayName)
                                .font(LifeOSType.rowTitle)
                                .foregroundStyle(primary)
                                .lineLimit(1)
                            // Prefixed when the last word was yours, so a
                            // thread you are waiting on is told apart from one
                            // waiting on you without inventing a read state
                            // the schema does not have.
                            Text(thread.theirsIsLast
                                 ? thread.lastMessage.body
                                 : "You: \(thread.lastMessage.body)")
                                .font(LifeOSType.label.weight(.regular))
                                .foregroundStyle(secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(Self.stamp(thread.lastMessage.createdAt))
                            .font(LifeOSType.caption)
                            .foregroundStyle(secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .font(LifeOSType.eyebrow)
            .tracking(0.8)
            .foregroundStyle(secondary)
    }

    /// A clock time today, a weekday this week, a date before that. A full
    /// date on every row would be the same eleven characters repeated down
    /// the screen, saying nothing about which message is newer.
    static func stamp(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let week = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
           date >= week {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A 38pt pastel circle carrying the first letter of a name, coloured by a
/// stable hash of that name so the same person is always the same colour.
///
/// `String.hashValue` is randomised per launch, which would make a friend a
/// different colour every time the app opens, so the hash is hand-rolled from
/// the name's bytes. Lifted out of `FriendsScreen` so the inbox draws people
/// the same way the friends list does.
struct InitialBubble: View {
    let name: String
    var size: CGFloat = 38

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hue = Self.stableHue(for: name)
        let letter = name.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased() ?? "?"
        Text(letter)
            .font(LifeOSType.rowTitle)
            .foregroundStyle(hue.top)
            .frame(width: size, height: size)
            .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))
    }

    static func stableHue(for name: String) -> ModuleHue {
        let hash = name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        let index = abs(hash) % ModuleHue.allCases.count
        return ModuleHue.allCases[index]
    }
}
