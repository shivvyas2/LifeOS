import SwiftUI
import DesignSystem
import Integrations

struct SocialHubScreen: View {
    enum Section: String, CaseIterable { case people = "People", groups = "Groups", rankings = "Rankings" }
    @State private var section: Section = .people
    @State private var model: GroupsViewModel
    @State private var creating = false
    @State private var selectedGroup: SocialGroup?
    @State private var openGroup = false
    @Environment(\.scenePhase) private var scenePhase

    init(activity: SocialActivitySnapshot?) { _model = State(initialValue: GroupsViewModel(activity: activity)) }

#if DEBUG
    init(preview model: GroupsViewModel) {
        _model = State(initialValue: model)
        _section = State(initialValue: .groups)
    }
#endif

    var body: some View {
        SocialCanvas {
            VStack(spacing: 0) {
                UnderlinePicker(selection: $section, options: Section.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 20).frame(maxWidth: 860)
                if section == .people {
                    FriendsScreen(embedded: true)
                } else {
                    groupsContent
                }
            }
        }
        .navigationTitle("Together")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { InboxScreen() } label: { Image(systemName: "tray") }
                    .accessibilityLabel("Messages and friend requests")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create group", systemImage: "plus") { creating = true }.labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $creating) {
            CreateGroupScreen { group in
                creating = false
                selectedGroup = group
                section = .groups
                openGroup = true
            }
        }
        .navigationDestination(isPresented: $openGroup) {
            if let selectedGroup {
                GroupDetailScreen(group: selectedGroup, activity: model.activity,
                                  startsWithBoard: section == .rankings)
            }
        }
        .task { await model.refresh() }
        .onChange(of: openGroup) { _, open in if !open { Task { await model.refresh() } } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
    }

    private var groupsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SocialHeading(title: section == .rankings ? "Friendly competition." : "Better together.",
                              detail: section == .rankings ? "Your groups. Your progress. A little motivation." : "Small wins and good company. Find your circle.",
                              icon: section == .rankings ? "trophy.fill" : "person.2.fill")
                if let error = model.error { SocialNotice(message: error) { Task { await model.refresh() } } }
                if model.loading { ProgressView().frame(maxWidth: .infinity).padding(32) }
                if section == .groups {
                    ForEach(model.groups.filter(\.isInvitation)) { group in
                        SocialPanel {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("GROUP INVITATION", systemImage: "envelope").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(group.name).lifeOSText(.screenTitle)
                                if !group.description.isEmpty { Text(group.description).lifeOSText(.secondary).foregroundStyle(.secondary) }
                                Text("Joining opens group chat. Health-score sharing starts off.").lifeOSText(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Decline") { Task { await model.answer(group, accept: false) } }.buttonStyle(.editorial(.secondary, size: .compact))
                                    Spacer()
                                    Button("Join group") { Task { await model.answer(group, accept: true) } }.buttonStyle(.editorial(.primary, size: .compact))
                                }.disabled(model.busy)
                            }
                        }
                    }
                }
                let joined = model.groups.filter { !$0.isInvitation }
                if joined.isEmpty && !model.loading {
                    SocialEmpty(title: section == .rankings ? "Your first leaderboard starts with a group" : "A space for your circle",
                                detail: "Create a group and invite friends, or accept an invitation to get started.", icon: "person.3.sequence")
                    Button { creating = true } label: {
                        Label("Create a group", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(.editorial(.primary, size: .compact))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)], spacing: 16) {
                    ForEach(joined) { group in
                        Button { selectedGroup = group; openGroup = true } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    Image(systemName: section == .rankings ? "trophy.fill" : "person.3.fill")
                                        .font(.title2).frame(width: 52, height: 52)
                                        .background(.white.opacity(0.65), in: Circle())
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.headline)
                                }
                                Text(group.name).lifeOSText(.screenTitle).fixedSize(horizontal: false, vertical: true)
                                Text(section == .rankings ? "Effort · Recharge · Rest" : group.description.isEmpty ? "A private space for your people." : group.description)
                                    .lifeOSText(.secondary).lineLimit(3)
                                HStack {
                                    Text(section == .rankings ? "View leaderboard" : "Open conversation").font(.subheadline.bold())
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }.padding(.top, 6)
                            }
                            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(SocialTheme.ink)
                            .background(SocialTheme.color(for: group.id), in: RoundedRectangle(cornerRadius: 26))
                        }.buttonStyle(.plain)
                    }
                }
                ProfileActivitySharingCard(isOn: Binding(get: { model.sharesWithFriends },
                    set: { enabled in Task { await model.shareWithFriends(enabled) } }),
                    isBusy: model.busy || model.refreshing)
            }
            .padding(20).frame(maxWidth: 860).frame(maxWidth: .infinity)
        }
        .refreshable { await model.refresh() }
    }
}

struct CreateGroupScreen: View {
    var onCreated: (SocialGroup) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var people = FriendsViewModel()
    @State private var name = ""
    @State private var detail = ""
    @State private var invited = Set<UUID>()
    @State private var query = ""
    @State private var saving = false
    @State private var error: String?
    @State private var groupID = UUID()

    var body: some View {
        NavigationStack {
            SocialCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Make room for your people.").lifeOSText(.display)
                        Text("A private chat with an optional activity leaderboard.").lifeOSText(.secondary).foregroundStyle(.secondary)
                        if let error { SocialNotice(message: error) }
                        SocialPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                TextField("Group name", text: $name).font(.title3.weight(.semibold))
                                Divider()
                                TextField("What’s this group for? (optional)", text: $detail, axis: .vertical).lineLimit(2...4)
                                Text("\(name.count)/60 · Description \(detail.count)/240").lifeOSText(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack { Text("Invite friends").font(.headline); Spacer(); Text("\(invited.count) selected").lifeOSText(.caption).foregroundStyle(.secondary) }
                        Text("They’ll choose whether to join. You can invite more friends later.").lifeOSText(.secondary).foregroundStyle(.secondary)
                        if let warning = people.errorMessage { SocialNotice(message: warning) { Task { await people.refresh() } } }
                        TextField("Find a friend", text: $query).padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        if people.phase == .loading { ProgressView() }
                        if people.phase == .ready && people.friends.isEmpty {
                            Text("No friends yet. You can create the group now and invite people after connecting in People.").lifeOSText(.secondary).foregroundStyle(.secondary)
                        }
                        ForEach(people.friends.filter { query.isEmpty || $0.profile.displayName.localizedCaseInsensitiveContains(query) }, id: \.profile.id) { entry in
                            Button {
                                if invited.contains(entry.profile.id) { invited.remove(entry.profile.id) }
                                else if invited.count < 49 { invited.insert(entry.profile.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    SocialAvatar(profile: entry.profile)
                                    Text(entry.profile.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: invited.contains(entry.profile.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(LifeOSTokens.accent)
                                }.frame(minHeight: 52).contentShape(.rect)
                            }.buttonStyle(.plain).accessibilityAddTraits(invited.contains(entry.profile.id) ? .isSelected : [])
                        }
                    }
                    .padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively).disabled(saving)
            }
            .navigationTitle("New group").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Create") { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.unicodeScalars.count > 60 || detail.unicodeScalars.count > 240)
                    }
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await people.appear() }
        }
    }

    private func create() async {
        guard !saving, let api = SocialSession.api, let session = SocialSession.current, let user = UUID(uuidString: session.userID) else {
            error = "Sign in to create a group."; return
        }
        saving = true; defer { saving = false }
        do {
            let id = try await api.create(id: groupID, name: name, description: detail, invitees: Array(invited), token: session.accessToken)
            onCreated(SocialGroup(id: id, name: name, description: detail, ownerID: user,
                                  members: [.init(groupID: id, userID: user, status: "accepted", sharesActivity: false)]))
        } catch { self.error = SocialSession.reason(error) }
    }
}
