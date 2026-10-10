import SwiftUI
import SwiftData
import AccountUI
import DesignSystem
import FocusExperience
import Persistence
import Soundscape

/// Home: the week's focus as the masthead figure, a mood that starts a session
/// in one tap with its last settings, Resume last, a way into the full setup,
/// and the sessions so far.
struct FocusHomeView: View {
    let gate: AccountGate
    let session: FocusSession
    @Environment(\.colorScheme) private var scheme
    @State private var weekSeconds: TimeInterval = 0
    @State private var recent: [FocusSessionSnapshot] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "LifeOS Focus · This week", title: Self.duration(weekSeconds),
                                  detail: "Signed in as \(accountLabel).")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.x1) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        Button(mood.title) { Task { await account.quickStart(mood) } }
                            .buttonStyle(.editorial(.primary, fullWidth: true))
                    }
                }
                HStack(spacing: Space.x1) {
                    Button("Resume last") { Task { await account.quickStart(nil) } }
                        .buttonStyle(.editorial(.secondary, size: .compact))
                    Button("Set up a session") { account.openSetup() }
                        .buttonStyle(.editorial(.secondary, size: .compact))
                        .accessibilityIdentifier("focus.setup")
                }
                if !recent.isEmpty {
                    EditorialSectionHeader(title: "Recent")
                    VStack(spacing: 0) {
                        ForEach(recent, id: \.id) { row in
                            EditorialRow(Mood(rawValue: row.mood)?.title ?? row.mood,
                                         value: Self.duration(row.focusedSeconds))
                            Hairline()
                        }
                    }
                }
                Button("Sign out") { gate.signOut() }
                    .buttonStyle(.editorial(.quiet, size: .compact))
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .sheet(item: Bindable(account).request) { request in
            let mood = request.mood ?? account.model.preferences.lastMood
            FocusSetupSheet(initial: account.model.preferences.setup(for: mood),
                            preferences: account.model.preferences, taskTitle: nil) { setup in
                Task {
                    await account.model.start(setup, inputs: FocusInputs(), context: account.container.mainContext)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { account.model.isPresented }, set: { _ in })) {
            FocusSessionScreen(model: account.model)
        }
        // Per session object, so a new account's Home restores and loads its own.
        .task(id: ObjectIdentifier(session)) {
            await account.model.restore(context: account.container.mainContext)
            await reload()
        }
        .onChange(of: account.model.isPresented) { _, presented in if !presented { Task { await reload() } } }
    }

    /// What is here now, then again after a sync has brought in sessions
    /// recorded in LifeOS or on another device.
    private func reload() async {
        read()
        await session.syncNow()
        read()
    }

    private func read() {
        let store = FocusStore(context: account.container.mainContext)
        weekSeconds = (try? store.focusedSeconds(inWeekOf: .now)) ?? 0
        recent = (try? store.recent()) ?? []
    }

    private var account: FocusAccountSession { session.account }

    private var accountLabel: String { gate.session?.email ?? gate.session?.phone ?? "your account" }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
