import SwiftUI
import SwiftData
import AccountUI
import DesignSystem
import FocusExperience
import Persistence
import Soundscape

/// Home: the week's focus as the masthead figure, a mood to start in one tap,
/// Resume last, and the sessions so far.
struct FocusHomeView: View {
    let gate: AccountGate
    @Bindable var session: FocusSession
    @Environment(\.colorScheme) private var scheme
    @State private var weekSeconds: TimeInterval = 0
    @State private var recent: [FocusSessionSnapshot] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "LifeOS Focus · This week", title: Self.duration(weekSeconds),
                                  detail: "Signed in as \(account).")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.x1) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        Button(mood.title) { session.open(mood: mood) }
                            .buttonStyle(.editorial(.primary, fullWidth: true))
                    }
                }
                Button("Resume last") { session.open(mood: nil) }
                    .buttonStyle(.editorial(.secondary, size: .compact))
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
        .sheet(item: $session.request) { request in
            let mood = request.mood ?? session.model.preferences.lastMood
            FocusSetupSheet(initial: session.model.preferences.setup(for: mood),
                            preferences: session.model.preferences, taskTitle: nil) { setup in
                Task {
                    await session.model.start(setup, inputs: FocusInputs(), context: session.container.mainContext)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { session.model.isPresented }, set: { _ in })) {
            FocusSessionScreen(model: session.model)
        }
        .task { await session.model.restore(context: session.container.mainContext); reload() }
        .onChange(of: session.model.isPresented) { _, presented in if !presented { reload() } }
    }

    private func reload() {
        let store = FocusStore(context: session.container.mainContext)
        weekSeconds = (try? store.focusedSeconds(inWeekOf: .now)) ?? 0
        recent = (try? store.recent()) ?? []
        session.syncNow()
    }

    private var account: String { gate.session?.email ?? gate.session?.phone ?? "your account" }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
