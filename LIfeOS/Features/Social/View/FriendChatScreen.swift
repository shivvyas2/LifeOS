import SwiftUI
import DesignSystem
import Integrations

/// One conversation with one friend: bubbles, a composer, a 5-second poll
/// while the screen is open. Echoes `AssistantSheet`'s idiom — same bubble
/// shapes, same capsule composer — because a message thread and the
/// assistant's chat are the same kind of surface.
struct FriendChatScreen: View {
    @State var model: ChatViewModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var composing: Bool

    init(friend: SocialProfile) {
        _model = State(initialValue: ChatViewModel(friend: friend))
    }

    var body: some View {
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
        .navigationTitle(model.friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        emptyState.padding(.top, 48)
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        VStack(alignment: .leading, spacing: 6) {
                            if let caption = dayCaption(at: index) {
                                Text(caption)
                                    .font(LifeOSType.caption)
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                    .frame(maxWidth: .infinity)
                            }
                            bubble(message)
                        }
                        .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        Text("Say hi to \(model.friend.displayName).")
            .font(LifeOSType.secondary)
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// A quiet caption above the first message of a new day. `nil` for the
    /// conversation's very first message when it does not need one, and for
    /// every message that falls on the same day as the one before it.
    private func dayCaption(at index: Int) -> String? {
        let calendar = Calendar.current
        let message = model.messages[index]
        if index == 0 {
            return Self.dayFormatter.string(from: message.createdAt)
        }
        let previous = model.messages[index - 1]
        guard !calendar.isDate(message.createdAt, inSameDayAs: previous.createdAt) else { return nil }
        return Self.dayFormatter.string(from: message.createdAt)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func bubble(_ message: SocialMessage) -> some View {
        let mine = message.sender == model.myUserID
        return Text(message.body)
            .font(LifeOSType.secondary)
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(mine
                          ? AnyShapeStyle(LifeOSTokens.accentSoft.resolve(scheme))
                          : AnyShapeStyle(.ultraThinMaterial))
            )
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: Bindable(model).draft, axis: .vertical)
                .font(LifeOSType.secondary)
                .focused($composing)
                .lineLimit(1...4)
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(LifeOSType.screenTitle.weight(.regular))
                    .foregroundStyle(LifeOSTokens.fabFill.resolve(scheme))
            }
            .disabled(model.sending || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
