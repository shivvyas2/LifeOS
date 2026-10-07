import SwiftUI
import UIKit
import DesignSystem
import Integrations

/// Where Today's Inbox gets its mail: Gmail, or a stub on the preview page.
@MainActor
protocol InboxSource: AnyObject {
    var isConnected: Bool { get }
    var changeCount: Int { get }
    func inbox(force: Bool) async -> InboxState
}

extension GmailConnectionViewModel: InboxSource {}

/// The important mail of the last two days: NEEDS YOU, then FYI.
struct InboxRows: View {
    let state: InboxState
    var onReconnect: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Inbox") {
                if case .ready(let digest, _) = state {
                    Text(MailDigest.countLine(digest.needsYouCount))
                        .font(LifeOSType.label).monospacedDigit().foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            switch state {
            case .notConnected, .loading:
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            case .reconnect:
                Button(action: onReconnect) {
                    HStack {
                        Text("Gmail needs reconnecting").font(LifeOSType.rowTitle)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(LifeOSTokens.accent)
                }
                .buttonStyle(.plain)
            case .unavailable:
                Text("Gmail could not be reached.").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
            case .ready(let digest, _):
                if digest.needsYou.isEmpty && digest.fyi.isEmpty {
                    Text("No important mail in the last two days.")
                        .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                }
                group("NEEDS YOU", digest.needsYou)
                group("FYI", digest.fyi)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [MailDigest.Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title).font(LifeOSType.label).foregroundStyle(Editorial.quietInk(scheme))
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows) { row(for: $0) }
            }
        }
    }

    private func row(for row: MailDigest.Row) -> some View {
        Button { open(row.item) } label: {
            VStack(alignment: .leading, spacing: Space.half) {
                HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                    if row.item.isUnread {
                        Circle().fill(LifeOSTokens.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    Text("\(row.item.sender) · \(row.item.subject)").font(LifeOSType.rowTitle).lineLimit(1)
                    Spacer(minLength: Space.x1)
                    Text(Self.when(row.item.receivedAt)).font(LifeOSType.label).monospacedDigit()
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
                Text(row.summary).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme)).lineLimit(2)
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inbox.row.\(row.item.id)")
        .accessibilityLabel("\(row.item.isUnread ? "Unread, " : "")\(row.item.sender), \(row.item.subject). \(row.summary)")
        .accessibilityHint("Opens in Gmail")
    }

    static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(.dateTime.hour().minute())
            : Calendar.current.isDateInYesterday(date) ? "Yesterday" : date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// The Gmail app when it is installed, the web inbox when not.
    private func open(_ item: MailItem) {
        if let app = URL(string: "googlegmail:///cv=\(item.threadId)"), UIApplication.shared.canOpenURL(app) {
            openURL(app)
        } else if let web = URL(string: "https://mail.google.com/mail/u/0/#inbox/\(item.threadId)") {
            openURL(web)
        }
    }
}

/// The preview page's mail: two that need you, three FYI.
@MainActor
final class StubInboxSource: InboxSource {
    let isConnected = true
    let changeCount = 0

    func inbox(force: Bool) async -> InboxState {
        let now = Date.now
        func item(_ id: String, _ sender: String, _ subject: String, minutesAgo: Double, unread: Bool) -> MailItem {
            MailItem(id: id, threadId: "t\(id)", sender: sender, senderEmail: "\(id)@example.com", subject: subject,
                     snippet: "", receivedAt: now.addingTimeInterval(-minutesAgo * 60), isUnread: unread)
        }
        let items = [
            item("1", "Priya Shah", "Contract for Thursday", minutesAgo: 25, unread: true),
            item("2", "Dr. Okafor's office", "Confirm your appointment", minutesAgo: 140, unread: true),
            item("3", "Sam", "Photos from the weekend", minutesAgo: 60, unread: false),
            item("4", "City Library", "Your hold is ready", minutesAgo: 300, unread: false),
            item("5", "Ana", "Notes from the call", minutesAgo: 900, unread: false),
        ]
        let verdicts: [String: MailVerdict] = [
            "1": MailVerdict(bucket: .needsYou, summary: "Priya needs the signed contract back before Thursday."),
            "2": MailVerdict(bucket: .needsYou, summary: "Reply to confirm Tuesday's 10:30 appointment."),
            "3": MailVerdict(bucket: .fyi, summary: "Sam shared the weekend's photos."),
            "4": MailVerdict(bucket: .fyi, summary: "A book you reserved is waiting at the front desk."),
            "5": MailVerdict(bucket: .fyi, summary: "Ana's notes and next steps from Monday's call."),
        ]
        return .ready(MailDigest.make(items: items, verdicts: verdicts), fetchedAt: now)
    }
}
