import SwiftUI
import DesignSystem
import Integrations
import Persistence

/// Who is in the project. The owner adds friends and removes members.
struct ProjectMembersSheet: View {
    @Bindable var model: ProjectsViewModel
    let projectID: UUID
    let isOwner: Bool
    @State private var friends = FriendsViewModel()
    @State private var revision = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var members: [ProjectMemberSnapshot] {
        _ = revision
        return (try? model.store?.members(projectID: projectID)) ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Members") {
                    ForEach(members) { member in
                        HStack {
                            MemberAvatars(names: [model.name(member.userID)], limit: 1)
                            Text(model.name(member.userID)).font(LifeOSType.rowTitle)
                            Spacer()
                            if member.role == "owner" {
                                Text("Owner").editorialEyebrow()
                            } else if isOwner {
                                Button("Remove", role: .destructive) {
                                    model.removeMember(member.userID, from: projectID); revision += 1
                                }
                            }
                        }
                    }
                }
                if isOwner {
                    Section("Add a friend") {
                        let inProject = Set(members.map(\.userID))
                        let candidates = friends.friends.filter { !inProject.contains($0.profile.userID) }
                        if candidates.isEmpty {
                            Text("Friends you add in Social show here.").font(LifeOSType.secondary)
                        }
                        ForEach(candidates, id: \.profile.userID) { friend in
                            Button {
                                model.addMember(friend.profile.userID, name: friend.profile.displayName, to: projectID)
                                revision += 1
                            } label: {
                                Label(friend.profile.displayName, systemImage: "plus")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await friends.appear() }
        }
    }
}
