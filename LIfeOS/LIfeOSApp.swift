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
            RootView()
                .task { await seedIfEmpty() }
        }
        .modelContainer(container)
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
