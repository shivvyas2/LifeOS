import SwiftUI
import DesignSystem
import Integrations

struct FriendChatScreen: View {
    @State var model: ChatViewModel
    @State private var loading = true
    @State private var followLatest = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(friend: SocialProfile) { _model = State(initialValue: ChatViewModel(friend: friend)) }
    private var timeline: [SocialMessage] { model.messages + model.pending }

    var body: some View {
        SocialCanvas {
            VStack(spacing: 0) {
                if let error = model.errorMessage {
                    SocialNotice(message: error) { Task { await model.refresh() } }.padding(.horizontal, 20).frame(maxWidth: 780)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if loading { ProgressView().padding(32) }
                            if timeline.isEmpty && !loading {
                                SocialEmpty(title: "Say hello to \(model.friend.displayName)", detail: "A little encouragement goes a long way.", icon: "bubble.left.and.bubble.right")
                            }
                            ForEach(Array(timeline.enumerated()), id: \.element.id) { index, message in
                                VStack(spacing: 12) {
                                    if index == 0 || !Calendar.current.isDate(message.createdAt, inSameDayAs: timeline[index - 1].createdAt) {
                                        Text(message.createdAt, format: .dateTime.month(.abbreviated).day()).lifeOSText(.caption).foregroundStyle(.secondary)
                                    }
                                    SocialMessageBubble(text: message.body, date: message.createdAt, mine: message.sender == model.myUserID)
                                    if message.id < 0 { Text("Sending…").lifeOSText(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }
                                }.id(message.id)
                            }
                        }
                        .padding(20).frame(maxWidth: 780).frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height - $0.visibleRect.maxY < 140 } action: { _, value in followLatest = value }
                    .onChange(of: timeline.last?.id) { _, id in
                        if let id, followLatest || timeline.last?.sender == model.myUserID {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            SocialComposer(draft: Bindable(model).draft, sending: model.sending) { Task { await model.send() } }
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .navigationTitle(model.friend.displayName).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { UserProfileScreen(profile: model.friend) } label: { SocialAvatar(profile: model.friend, size: 32) }
                    .accessibilityLabel("View \(model.friend.displayName)’s profile")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                loading = false
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
