import SwiftUI
import DesignSystem
import Integrations

struct GroupDetailScreen: View {
    enum Section: String, CaseIterable { case chat = "Chat", board = "Leaderboard", members = "Members" }
    @State private var model: GroupViewModel
    @State private var section: Section
    @State private var inviting = false
    @State private var leaving = false
    @State private var removal: SocialProfile?
    @State private var confirmingRemoval = false
    @State private var selectedProfile: SocialProfile?
    @State private var showProfile = false
    @State private var followLatest = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(group: SocialGroup, activity: SocialActivitySnapshot?, startsWithBoard: Bool = false) {
        _model = State(initialValue: GroupViewModel(group: group, activity: activity))
        _section = State(initialValue: startsWithBoard ? .board : .chat)
    }

#if DEBUG
    init(preview model: GroupViewModel, section: Section) {
        _model = State(initialValue: model)
        _section = State(initialValue: section)
    }
#endif

    var body: some View {
        SocialCanvas {
            VStack(spacing: 0) {
                UnderlinePicker(selection: $section, options: Section.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 20).frame(maxWidth: 860)
                if model.accessLost {
                    SocialEmpty(title: "This group is no longer available", detail: "You may have left or been removed. Return to your groups to continue.", icon: "person.crop.circle.badge.xmark")
                    Spacer()
                } else {
                    if let error = model.error {
                        SocialNotice(message: error) { Task { await model.refresh(); if section == .board { await model.loadBoard() } } }
                            .padding(.horizontal, 20).padding(.top, 12).frame(maxWidth: 860)
                    }
                    switch section {
                    case .chat: chat
                    case .board: leaderboard
                    case .members: members
                    }
                }
            }
        }
        .navigationTitle(model.group.name).navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                if section == .board { await model.loadBoard() }
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .task(id: section) { if section == .board { await model.loadBoard() } }
        .onChange(of: model.boardDate) { _, _ in model.board = []; Task { await model.loadBoard() } }
        .onChange(of: model.metric) { _, _ in model.board = []; Task { await model.loadBoard() } }
        .sheet(isPresented: $inviting) { inviteSheet }
        .navigationDestination(isPresented: $showProfile) { if let selectedProfile { UserProfileScreen(profile: selectedProfile) } }
        .confirmationDialog("Leave \(model.group.name)?", isPresented: $leaving, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) { Task { if await model.leave() { dismiss() } } }
        } message: {
            Text(model.isOwner ? "Ownership passes to the longest-standing member. If you’re the last member, the group and chat are deleted." : "You’ll lose access to this chat and leaderboard. You’ll need a new invitation to return.")
        }
        .confirmationDialog("Remove this person?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            if let removal { Button("Remove \(removal.displayName)", role: .destructive) { Task { await model.remove(removal.id) } } }
        } message: { Text("They’ll lose access to this group’s chat and leaderboard.") }
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if model.hasOlder {
                        Button { Task { await model.older() } } label: {
                            if model.loadingOlder { ProgressView() } else { Text("Load earlier messages").lifeOSText(.secondary) }
                        }.frame(minHeight: 44).disabled(model.loadingOlder)
                    }
                    if model.loading { ProgressView().padding(30) }
                    if model.messages.isEmpty && !model.loading {
                        SocialEmpty(title: "Start the conversation", detail: model.group.description.isEmpty ? "Share a hello, a plan, or a small win." : model.group.description, icon: "bubble.left.and.bubble.right")
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        VStack(spacing: 12) {
                            if index == 0 || !Calendar.current.isDate(message.createdAt, inSameDayAs: model.messages[index - 1].createdAt) {
                                Text(message.createdAt, format: .dateTime.month(.abbreviated).day())
                                    .lifeOSText(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                            }
                            SocialMessageBubble(text: message.body, date: message.createdAt,
                                mine: message.sender == model.myID,
                                sender: model.profiles[message.sender]?.displayName ?? "Former member")
                        }.id(message.id)
                    }
                    if let failed = model.failedSend {
                        SocialPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(failed.body).lifeOSText(.secondary)
                                HStack {
                                    Label("Not confirmed", systemImage: "exclamationmark.circle").lifeOSText(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Retry") { Task { await model.send(retry: true) } }.disabled(model.sending)
                                }
                            }
                        }
                    }
                }
                .padding(20).frame(maxWidth: 780).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height - $0.visibleRect.maxY < 140 } action: { _, value in followLatest = value }
            .onChange(of: model.messages.last?.id) { _, id in
                if let id, followLatest || model.messages.last?.sender == model.myID {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            SocialComposer(draft: $model.draft, sending: model.sending,
                           disabled: model.accessLost || model.failedSend != nil) { Task { await model.send() } }
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
    }

    private var leaderboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill").font(.title2).foregroundStyle(LifeOSTokens.accent).accessibilityHidden(true)
                        Text("Leaderboard").lifeOSText(.screenTitle).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text(model.metric.detail).lifeOSText(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("Rank by", selection: $model.metric) {
                            ForEach(LeaderboardMetric.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).tint(LifeOSTokens.accent)
                    }
                }
                DatePicker("Compare day", selection: $model.boardDate,
                           in: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!...Date.now,
                           displayedComponents: [.date]).lifeOSText(.secondary)
                DisclosureGroup("How \(model.metric.title) works") {
                    Text(model.metric.explanation).lifeOSText(.secondary).foregroundStyle(.secondary).padding(.top, 8)
                }.lifeOSText(.rowTitle)
                Text("Daily app scores · out of 100").lifeOSText(.caption).foregroundStyle(.secondary)
                if model.loadingBoard && model.board.isEmpty {
                    ProgressView("Loading rankings…").frame(maxWidth: .infinity).padding(28)
                } else if model.board.isEmpty {
                    SocialEmpty(title: "Room at the starting line", detail: "No eligible readings for this day yet. Connect Apple Health, WHOOP or Fitbit in your profile and enable score sharing below. Recharge needs 7 earlier days of same-source HRV and resting heart rate. Missing readings stay unranked.", icon: "chart.bar.xaxis")
                } else {
                    SocialLeaderboard(entries: model.board, metric: model.metric, myID: model.myID) { profile in
                        selectedProfile = profile; showProfile = true
                    }
                }
                SocialPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Share my health scores", isOn: Binding(get: { model.shares }, set: { enabled in Task { await model.share(enabled) } }))
                            .font(.subheadline.bold()).disabled(model.busy || model.loading || model.refreshing)
                        Text("Let this group see your Effort, Recharge and Rest scores, source and measurement day. Sharing starts off and can be stopped anytime.")
                            .lifeOSText(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.refreshable { await model.refresh(); await model.loadBoard() }
    }

    private var members: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SocialHeading(title: "The whole crew.", detail: model.group.description.isEmpty ? "Good company makes the difference." : model.group.description, icon: "person.2.fill")
                HStack {
                    Text("\(model.members.filter(\.isAccepted).count) members").font(.headline)
                    Spacer()
                    if model.isOwner { Button("Invite friends", systemImage: "person.badge.plus") { inviting = true }.lifeOSText(.secondary) }
                }
                SocialPanel {
                    VStack(spacing: 0) {
                        ForEach(model.members) { member in
                            HStack(spacing: 12) {
                                if let profile = model.profiles[member.userID] {
                                    Button { selectedProfile = profile; showProfile = true } label: {
                                        HStack(spacing: 12) {
                                            SocialAvatar(profile: profile)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(profile.displayName).lifeOSText(.rowTitle).foregroundStyle(.primary)
                                                Text(!member.isAccepted ? "Invited" : member.userID == model.group.ownerID ? "Owner" : "Member")
                                                    .lifeOSText(.caption).foregroundStyle(.secondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                                    }.buttonStyle(.plain)
                                    if model.isOwner && member.userID != model.myID {
                                        Button("Remove", systemImage: "person.badge.minus") { removal = profile; confirmingRemoval = true }
                                            .labelStyle(.iconOnly).frame(width: 44, height: 44).accessibilityLabel("Remove \(profile.displayName)")
                                    }
                                }
                            }.padding(.vertical, 12)
                            if member.id != model.members.last?.id { Divider() }
                        }
                    }
                }
                Button("Leave group", role: .destructive) { leaving = true }
                    .frame(minHeight: 48).disabled(model.busy)
            }.padding(20).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
    }

    private var inviteSheet: some View {
        GroupInviteScreen(model: model)
    }
}

private struct GroupInviteScreen: View {
    @Bindable var model: GroupViewModel
    @State private var people = FriendsViewModel()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SocialCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Invite to \(model.group.name)").font(.title2.bold())
                        Text("Your friends decide whether to join.").lifeOSText(.secondary).foregroundStyle(.secondary)
                        if let error = model.error ?? people.errorMessage { SocialNotice(message: error) }
                        if people.phase == .loading { ProgressView() }
                        if people.phase == .ready && people.friends.isEmpty {
                            SocialEmpty(title: "Connect first", detail: "Find and add friends from People, then invite them here.", icon: "person.badge.plus")
                        }
                        ForEach(people.friends, id: \.profile.id) { entry in
                            HStack(spacing: 12) {
                                SocialAvatar(profile: entry.profile)
                                Text(entry.profile.displayName).font(.subheadline.weight(.medium))
                                Spacer()
                                if model.members.contains(where: { $0.userID == entry.profile.id }) {
                                    Text("Added").lifeOSText(.caption).foregroundStyle(.secondary)
                                } else {
                                    Button("Invite") { Task { await model.invite(entry.profile.id) } }
                                        .buttonStyle(.editorial(.secondary, size: .compact)).disabled(model.busy)
                                }
                            }.frame(minHeight: 56)
                        }
                    }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Invite friends").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await people.appear() }
        }
    }
}

struct SocialMessageBubble: View {
    let text: String
    let date: Date
    let mine: Bool
    var sender: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if mine { Spacer(minLength: 44) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 7) {
                if !mine, let sender {
                    Text(sender).lifeOSText(.rowTitle).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
                Text(text).lifeOSText(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .foregroundStyle(mine ? Color.white : (scheme == .dark ? .white : SocialTheme.ink))
                    .background(mine ? SocialTheme.ink : SocialTheme.paper(scheme),
                        in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: mine ? 22 : 6,
                                                   bottomTrailingRadius: mine ? 6 : 22, topTrailingRadius: 22))
                    .overlay {
                        if mine { UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22)
                            .strokeBorder(.white.opacity(scheme == .dark ? 0.18 : 0)) }
                    }
                Text(date, format: .dateTime.hour().minute()).lifeOSText(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            if !mine { Spacer(minLength: 44) }
        }.accessibilityElement(children: .combine)
    }
}

struct SocialComposer: View {
    @Binding var draft: String
    let sending: Bool
    var disabled = false
    var send: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if draft.unicodeScalars.count > 1800 {
                Text("\(draft.unicodeScalars.count)/2,000").lifeOSText(.caption).foregroundStyle(draft.unicodeScalars.count > 2000 ? .red : .secondary)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Write a message…", text: $draft, axis: .vertical).lineLimit(1...5).lifeOSText(.body)
                    .padding(.vertical, 12).padding(.leading, 8).accessibilityLabel("Message")
                Button(action: send) {
                    Group { if sending { ProgressView().tint(SocialTheme.ink) } else { Image(systemName: "arrow.up").font(.headline) } }
                        .foregroundStyle(SocialTheme.ink).frame(width: 48, height: 48)
                        .background(LifeOSTokens.accent, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                .accessibilityLabel("Send message")
                .disabled(disabled || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 2000)
                .opacity(disabled || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 2000 ? 0.45 : 1)
            }
            .padding(8).background(SocialTheme.paper(scheme), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.08)))
        }.padding(.horizontal, 16).padding(.bottom, 10)
    }
}
