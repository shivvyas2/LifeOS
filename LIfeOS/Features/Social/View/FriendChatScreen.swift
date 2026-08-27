import SwiftUI
import DesignSystem
import Integrations

/// One conversation with one friend: frosted bubbles floating on a night
/// aurora, a dark glass composer, a 5-second poll while the screen is open.
struct FriendChatScreen: View {
    @State var model: ChatViewModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var composing: Bool

    /// The user's three colors, exactly. Local to this screen rather than a
    /// `DesignSystem` token: this aurora belongs to chat alone.
    private static let night = Color(red: 5 / 255, green: 10 / 255, blue: 48 / 255)
    private static let blue = Color(red: 0, green: 0, blue: 1)
    private static let cyan = Color(red: 0, green: 1, blue: 1)

    init(friend: SocialProfile) {
        _model = State(initialValue: ChatViewModel(friend: friend))
    }

    var body: some View {
        ZStack {
            aurora
            VStack(spacing: 0) {
                conversation
                if let error = model.errorMessage {
                    Text(error)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                composer
            }
        }
        .navigationTitle(model.friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Deep night dominant, a cyan bloom low on the leading side, blue
    /// sweeping the trailing side. A 3x3 mesh keeps the transitions soft and
    /// diffuse rather than a hard-edged gradient.
    private var aurora: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                Self.night, Self.night, Self.night,
                Self.night, Self.night, Self.blue,
                Self.cyan, Self.night, Self.blue,
            ]
        )
        .ignoresSafeArea()
    }

    /// Real rows, then whatever is still in flight, in the order they were
    /// sent. Kept as a computed list rather than merged into `model.messages`
    /// itself, so a poll landing mid-send can never lose the optimistic row.
    private var timeline: [SocialMessage] {
        model.messages + model.pending
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if timeline.isEmpty {
                        emptyState.padding(.top, 48)
                    }
                    ForEach(Array(timeline.enumerated()), id: \.element.id) { index, message in
                        VStack(alignment: .leading, spacing: 6) {
                            if let caption = dayCaption(at: index) {
                                Text(caption)
                                    .font(LifeOSType.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                            }
                            bubble(message)
                        }
                        .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: timeline.count) {
                if let last = timeline.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        Text("Say hi to \(model.friend.displayName).")
            .font(LifeOSType.secondary)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// One centered label when the day changes between consecutive messages
    /// in the timeline; `nil` otherwise, since each bubble already carries
    /// its own time.
    private func dayCaption(at index: Int) -> String? {
        let calendar = Calendar.current
        let message = timeline[index]
        if index == 0 {
            return Self.dayFormatter.string(from: message.createdAt)
        }
        let previous = timeline[index - 1]
        guard !calendar.isDate(message.createdAt, inSameDayAs: previous.createdAt) else { return nil }
        return Self.dayFormatter.string(from: message.createdAt)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// A frosted pill floating on the aurora: theirs is plain glass, mine
    /// gets a white wash over the same glass so it reads brighter without
    /// introducing a second material. The time sits inside, trailing, quiet.
    private func bubble(_ message: SocialMessage) -> some View {
        let mine = message.sender == model.myUserID
        return HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(message.body)
                .font(LifeOSType.secondary)
                .foregroundStyle(.white)
            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(LifeOSType.eyebrow.weight(.regular))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(mine ? 0.22 : 0))
                )
        )
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Your message…", text: Bindable(model).draft, axis: .vertical)
                .font(LifeOSType.secondary)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($composing)
                .lineLimit(1...4)
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(LifeOSType.rowTitle.weight(.bold))
                    .foregroundStyle(Self.night)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Self.cyan))
            }
            .disabled(model.sending || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.35))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
