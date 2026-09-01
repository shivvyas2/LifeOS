//
//  LIfeOSApp.swift
//  LIfeOS
//
//  Created by Shiv Vyas on 8/10/26.
//

import SwiftUI
import SwiftData
import OSLog
import Persistence

private let appLog = Logger(subsystem: "com.shivvyas.lifeos", category: "app")

@main
struct LIfeOSApp: App {
    /// Which account's store is open, and the store itself.
    ///
    /// Both are state rather than constants because switching accounts
    /// replaces the container. A store belongs to one account, so the only way
    /// to change accounts is to open a different file and rebuild the tree
    /// above it.
    @State private var session = AccountSession()

    /// APNs has no SwiftUI entry point: the device token arrives through a
    /// UIKit delegate callback and nowhere else. This is the whole reason the
    /// app has a delegate at all.
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate

    init() {
        // Demo default for TestFlight: the Money tab opens on sample figures,
        // so there is something to walk a person through before any bank is
        // connected. An attached bank overrides it, and Settings turns it off.
        UserDefaults.standard.register(defaults: [MoneyViewModel.sampleDataKey: true])

    }

    var body: some Scene {
        WindowGroup {
            if let container = session.container {
                AppShell(onSignedIn: { session.signIn($0, session: $1) },
                         onSignedOut: { session.signOut() },
                         hasStore: true)
                    .modelContainer(container)
                    // Re-rooted per account, so no screen carries the previous
                    // account's view models or scroll position into the next
                    // one. A stale snapshot on screen after a switch is the
                    // same class of leak as a stale row.
                    .id(session.scope?.id ?? "none")
                    .environment(\.accountSession, session)
                    .task(id: session.scope?.id) { purgeSeededHistoryOnce() }
            } else {
                // Nobody signed in. The onboarding flow needs no store: it has
                // nothing to read and nowhere to put anything until there is
                // an account to put it in.
                AppShell(onSignedIn: { session.signIn($0, session: $1) },
                         onSignedOut: { session.signOut() },
                         hasStore: false)
            }
        }
        // Hardware keyboard support lives in the scene so the shortcuts work
        // wherever focus is, and so iPadOS lists them in the overlay that
        // appears when Command is held.
        .commands { NotesCommands() }
    }

    /// Key for the one-time removal of the fabricated history the app used to
    /// seed. Named for what it did rather than when, so it reads sensibly in a
    /// defaults dump years from now.
    private static let purgedSeededHistoryKey = "didPurgeSeededHealthHistory"

    /// Clears the sixty days of invented health data a first launch used to
    /// write, once, on the first run of a build that no longer seeds.
    ///
    /// The days are not merely wrong to look at: most health fields are
    /// `fillGapsOnly`, so Apple Health declines to overwrite a day that already
    /// has a value, and every seeded day refused the real reading for as long
    /// as it sat there. Removing them is what lets the real numbers arrive.
    ///
    /// The Health sync cursor is reset with them. Without that, the next sync
    /// would re-read only the days since the last one and leave the rest of the
    /// month blank, which would look exactly like the purge had broken the app.
    @MainActor
    private func purgeSeededHistoryOnce() {
        // Per account: one person's history being purged says nothing
        // about another's.
        let defaults = UserDefaults.currentAccount
        guard !defaults.bool(forKey: Self.purgedSeededHistoryKey) else { return }

        do {
            guard let container = session.container else { return }
            let removed = try SampleMetricsPurge.run(context: container.mainContext)
            defaults.set(true, forKey: Self.purgedSeededHistoryKey)
            defaults.removeObject(forKey: HealthConnectionViewModel.lastSyncKey)
            appLog.info("purged \(removed, privacy: .public) seeded day rows")
        } catch {
            // Left unflagged on failure, so the next launch tries again rather
            // than leaving invented data in place for good.
            appLog.error("seeded history purge failed: \(String(describing: error), privacy: .public)")
        }
    }
}
