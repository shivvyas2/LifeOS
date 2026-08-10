import Foundation
import SwiftData
import Persistence

@MainActor @Observable
final class PlanViewModel {
    private(set) var snapshot = PlanSnapshot()
    var section: PlanSection = .goals

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load() {
        guard let context else { return }
        let store = PlanStore(context: context, calendar: calendar)

        do {
            // Habits carry their recent history so the dot strip renders from
            // the snapshot rather than querying per row.
            let habitEntries = try store.entries(kind: .habit)
            var habits: [PlanItemSnapshot] = []
            var streaks: [UUID: Int] = [:]
            for entry in habitEntries {
                habits.append(entry.snapshot(recentTicks: try store.recentTicks(for: entry, days: 14)))
                streaks[entry.id] = try store.streak(for: entry)
            }

            snapshot = PlanSnapshot(
                goals: try store.entries(kind: .goal).map { $0.snapshot() },
                habits: habits,
                notes: try store.entries(kind: .note).map { $0.snapshot() },
                content: try store.entries(kind: .content).map { $0.snapshot() },
                streaks: streaks
            )
        } catch {
            assertionFailure("Plan load failed: \(error)")
        }
    }

    func add(title: String, detail: String?, target: Double?) {
        guard let context, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try PlanStore(context: context, calendar: calendar).add(
                kind: section.kind,
                title: title,
                detail: detail?.isEmpty == true ? nil : detail,
                status: section == .content ? .scheduled : .todo,
                progressValue: target != nil ? 0 : nil,
                progressTarget: target
            )
            load()
        } catch {
            assertionFailure("Plan add failed: \(error)")
        }
    }

    func toggleHabit(id: UUID) {
        mutate(id: id) { store, entry in try store.toggleTick(for: entry) }
    }

    func advance(id: UUID) {
        mutate(id: id) { store, entry in
            // Goals step through their milestones; everything else toggles done.
            if let target = entry.progressTarget {
                entry.progressValue = min((entry.progressValue ?? 0) + 1, target)
                entry.status = (entry.progressValue ?? 0) >= target ? .done : .inProgress
                try store.setStatus(entry.status, on: entry)
            } else {
                try store.setStatus(entry.status == .done ? .todo : .done, on: entry)
            }
        }
    }

    func delete(id: UUID) {
        mutate(id: id) { store, entry in try store.delete(entry) }
    }

    private func mutate(id: UUID, _ work: (PlanStore, PlanEntry) throws -> Void) {
        guard let context else { return }
        do {
            let entry = try context.fetch(
                FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.id == id })
            ).first
            guard let entry else { return }
            try work(PlanStore(context: context, calendar: calendar), entry)
            load()
        } catch {
            assertionFailure("Plan mutation failed: \(error)")
        }
    }
}
