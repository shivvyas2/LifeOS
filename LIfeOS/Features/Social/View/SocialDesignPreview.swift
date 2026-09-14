#if DEBUG
import SwiftUI
import Integrations
import DesignSystem

/// Sample-only layout fixtures. The preview models never load account data.
struct SocialDesignPreview: View {
    @State private var screen = ProcessInfo.processInfo.arguments.contains("--preview-friends") ? 4 : ProcessInfo.processInfo.arguments.contains("--preview-chat") ? 1 : ProcessInfo.processInfo.arguments.contains("--preview-board") ? 2 : ProcessInfo.processInfo.arguments.contains("--preview-members") ? 3 : 0
    @State private var largeText = ProcessInfo.processInfo.arguments.contains("--preview-large")
    private let owner = UUID(uuidString: "a6140000-0000-4000-8000-000000000001")!
    private let friend = UUID(uuidString: "a6140000-0000-4000-8000-000000000002")!
    private let groupID = UUID(uuidString: "b6140000-0000-4000-8000-000000000001")!

    private var group: SocialGroup {
        SocialGroup(id: groupID, name: "The morning crew", description: "Small wins, early walks, and a little encouragement.", ownerID: owner,
                    members: [.init(groupID: groupID, userID: owner, status: "accepted", sharesActivity: false)])
    }
    private func detailModel() -> GroupViewModel {
        let model = GroupViewModel(group: group, activity: nil)
        model.previewMode = true; model.loading = false
        model.members = [.init(groupID: groupID, userID: owner, status: "accepted", sharesActivity: true, sharesWellness: true),
                         .init(groupID: groupID, userID: friend, status: "accepted", sharesActivity: true, sharesWellness: true)]
        model.profiles = [owner: SocialProfile(userID: owner, displayName: "Alex Morgan"), friend: SocialProfile(userID: friend, displayName: "Jamie Chen")]
        model.messages = [
            .init(id: 1, groupID: groupID, sender: owner, body: "Anyone up for a walk before the day gets busy?", clientID: UUID(), createdAt: .now.addingTimeInterval(-1600)),
            .init(id: 2, groupID: groupID, sender: friend, body: "I’m in! Let’s do the park loop at 8.", clientID: UUID(), createdAt: .now.addingTimeInterval(-1500)),
            .init(id: 3, groupID: groupID, sender: owner, body: "Perfect. No pace goals today — just some fresh air and a catch-up.", clientID: UUID(), createdAt: .now.addingTimeInterval(-1300))]
        let tied = ProcessInfo.processInfo.arguments.contains("--preview-ties")
        model.board = [
            .init(userID: owner, displayName: "Alex Morgan", score: 92, position: 1, updatedAt: .now.addingTimeInterval(-1800), source: "whoop", day: SocialWellness.dayKey(.now)),
            .init(userID: friend, displayName: "Jamie Chen", score: tied ? 92 : 85, position: tied ? 1 : 2, updatedAt: .now.addingTimeInterval(-3600), source: "appleHealth", day: SocialWellness.dayKey(.now)),
            .init(userID: UUID(uuidString: "a6140000-0000-4000-8000-000000000003")!, displayName: "Sofia Rivera", score: 80, position: 3, updatedAt: .now.addingTimeInterval(-3600), source: "fitbit", day: SocialWellness.dayKey(.now)),
            .init(userID: UUID(uuidString: "a6140000-0000-4000-8000-000000000004")!, displayName: "Noah Williams", score: 72, position: 4, updatedAt: .now.addingTimeInterval(-3600), source: "appleHealth", day: SocialWellness.dayKey(.now)),
            .init(userID: UUID(uuidString: "a6140000-0000-4000-8000-000000000005")!, displayName: "Olivia Park", score: 65, position: 5, updatedAt: .now.addingTimeInterval(-3600), source: "appleHealth", day: SocialWellness.dayKey(.now))]
        return model
    }
    private func hubModel() -> GroupsViewModel {
        let model = GroupsViewModel(activity: nil)
        model.previewMode = true; model.loading = false
        model.groups = [group, .init(id: UUID(), name: "Weekend reset", description: "A little space to make plans for the weekend.", ownerID: friend,
                                    members: [.init(groupID: UUID(), userID: owner, status: "invited", sharesActivity: false)])]
        return model
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SAMPLE SOCIAL").lifeOSText(.caption)
                Picker("Screen", selection: $screen) {
                    Text("Groups").tag(0); Text("Chat").tag(1); Text("Rankings").tag(2); Text("Members").tag(3); Text("Friends").tag(4)
                }.pickerStyle(.menu)
                Spacer()
                Toggle("Large text", isOn: $largeText).labelsHidden().accessibilityLabel("Large text")
            }.padding(.horizontal, 20).padding(.vertical, 6).dynamicTypeSize(.large)
            NavigationStack {
                switch screen {
                case 1: GroupDetailScreen(preview: detailModel(), section: .chat)
                case 2: GroupDetailScreen(preview: detailModel(), section: .board)
                case 3: GroupDetailScreen(preview: detailModel(), section: .members)
                case 4: FriendsScreen(preview: .designPreview())
                default: SocialHubScreen(preview: hubModel())
                }
            }.id(screen)
        }
        .dynamicTypeSize(largeText ? .accessibility1 : .large)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--preview-dark") ? .dark : .light)
    }
}
#Preview { SocialDesignPreview() }
#endif
