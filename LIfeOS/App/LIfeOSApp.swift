//
//  LIfeOSApp.swift
//  LIfeOS
//
//  Created by Shiv Vyas on 8/10/26.
//

import SwiftUI
import SwiftData
import Persistence

@main
struct LIfeOSApp: App {
    private let container: ModelContainer

    init() {
        // Demo default for TestFlight: the Money tab opens on sample figures,
        // so there is something to walk a person through before any bank is
        // connected. An attached bank overrides it, and Settings turns it off.
        UserDefaults.standard.register(defaults: [MoneyViewModel.sampleDataKey: true])

        do {
            container = try LifeOSContainer.make()
        } catch {
            // A container that cannot open is unrecoverable and always a
            // schema bug, never a user condition. Fail loudly during development.
            fatalError("Failed to create the model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .task { await seedIfEmpty() }
        }
        .modelContainer(container)
        // Hardware keyboard support lives in the scene so the shortcuts work
        // wherever focus is, and so iPadOS lists them in the overlay that
        // appears when Command is held.
        .commands { NotesCommands() }
    }

    @MainActor
    private func seedIfEmpty() async {
        let store = MetricsStore(context: container.mainContext)
        do {
            let existing = try store.metrics(from: .distantPast, to: .now)
            guard existing.isEmpty else { return }
            try SeedData.populate(store: store)
        } catch {
            print("Seed failed: \(error)")
        }
    }
}
