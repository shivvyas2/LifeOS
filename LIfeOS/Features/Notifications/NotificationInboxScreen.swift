import SwiftUI
import DesignSystem
import AppSurfaces

struct NotificationInboxScreen: View {
    @State private var service = PushService.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: InboxEntry?
    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AccountPageHeading(title: "A little heads-up.", detail: "Your coach’s check-ins, all in one place.")
                    notificationPermission
                    if service.entries.isEmpty {
                        AccountPanel {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: "bell.badge").font(.largeTitle).foregroundStyle(LifeOSTokens.accent)
                                Text("You’re all caught up").font(LifeOSType.sectionTitle)
                                Text("New coach notifications appear here. Open a check-in to continue with LIFO.")
                                    .font(LifeOSType.secondary).foregroundStyle(.secondary)
                            }.padding(.vertical, 16)
                        }
                    } else {
                        HStack {
                            Text(service.unreadCount == 0 ? "Recent" : "\(service.unreadCount) unread").font(LifeOSType.sectionTitle)
                            Spacer()
                            Button("Read all", action: service.markAllRead).font(LifeOSType.label)
                                .disabled(service.unreadCount == 0)
                        }
                        ForEach(service.entries) { entry in
                            Button { service.markRead(entry.id); selected = entry } label: {
                                AccountPanel {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: entry.isRead ? "sparkles" : "bell.badge.fill")
                                            .foregroundStyle(LifeOSTokens.accent).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("LIFO").font(LifeOSType.rowTitle)
                                                Spacer()
                                                Text(entry.receivedAt, style: .date).font(LifeOSType.caption).foregroundStyle(.secondary)
                                            }
                                            Text(entry.text).font(LifeOSType.body).multilineTextAlignment(.leading)
                                            Label("Open check-in", systemImage: "arrow.up.right").font(LifeOSType.label)
                                                .foregroundStyle(LifeOSTokens.accent)
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(entry.isRead ? "Read" : "Unread") check-in. \(entry.text)")
                        }
                        Button("Clear read notifications", action: service.clearRead)
                            .font(LifeOSType.label).padding(.vertical, 10)
                    }
                    Text("Shows notifications received on this device for your account.")
                        .font(LifeOSType.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: 680).frame(maxWidth: .infinity).padding(20)
            }
        }
        .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
        .tint(LifeOSTokens.accent)
        .task { await service.refreshInbox() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await service.refreshInbox() } } }
        .fullScreenCover(item: $selected) { entry in NotificationCoachScreen(entry: entry) }
    }
    private var notificationPermission: some View {
        AccountPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bell").foregroundStyle(LifeOSTokens.accent).font(.title2)
                VStack(alignment: .leading, spacing: 7) {
                    Text(service.authorization == .authorized ? "Check-ins are on" : "Make room for a check-in").font(LifeOSType.rowTitle)
                    Text("Choose banners, sounds and Lock Screen previews in iOS Settings.")
                        .font(LifeOSType.secondary).foregroundStyle(.secondary)
                    Button(service.authorization == .notDetermined ? "Enable notifications" : "Notification settings") {
                        if service.authorization == .notDetermined { Task { await service.requestAuthorization() } }
                        else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(LifeOSType.rowTitle).padding(.top, 3)
                }
            }
        }
    }
}

private struct NotificationCoachScreen: View {
    let entry: InboxEntry
    @State private var coach = CoachViewModel()
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LifoCoachScreen(model: coach, onDismiss: { dismiss() })
            .task { coach.attach(context); coach.seed(entry.text) }
    }
}
