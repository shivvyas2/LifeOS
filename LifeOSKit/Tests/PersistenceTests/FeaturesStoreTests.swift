import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct FeaturesStoreTests {
    private let me = UUID()
    private func store() throws -> ProjectsStore {
        ProjectsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }
    private func project(_ store: ProjectsStore) throws -> UUID {
        try store.createProject(name: "LifeOS", scope: "Ship it", colour: "moss", ownerID: me)
    }

    @Test func featuresKeepTheirPlanOrder() throws {
        let store = try store()
        let p = try project(store)
        let a = try store.createFeature(projectID: p, title: "Sign in")
        let b = try store.createFeature(projectID: p, title: "Credit cards")
        let c = try store.createFeature(projectID: p, title: "Widgets")
        try store.moveFeature(id: c, to: 0)
        #expect(try store.features(projectID: p).map(\.id) == [c, a, b])
        #expect(try store.features(projectID: p).map(\.position) == [0, 1, 2])
    }

    @Test func aNewFeatureIsPlanned() throws {
        let store = try store()
        let p = try project(store)
        let id = try store.createFeature(projectID: p, title: "Sign in", note: "Apple and email")
        let feature = try #require(try store.feature(id: id))
        #expect(feature.stage == .planned)
        #expect(feature.stageDetail == "")
        #expect(feature.note == "Apple and email")
        #expect(feature.branch == nil)
    }

    /// Review Focus 1: the server counts scalars; a title it would refuse
    /// never leaves the phone.
    @Test func aLongEmojiTitleIsCutToEightyScalars() throws {
        let store = try store()
        let p = try project(store)
        let title = String(repeating: "👩🏽‍💻", count: 30)   // 4 scalars each
        let id = try store.createFeature(projectID: p, title: title)
        let saved = try #require(try store.feature(id: id)).title
        #expect(saved.unicodeScalars.count <= 80)
        #expect(saved.unicodeScalars.count == 80)
        try store.updateFeature(id: id, note: String(repeating: "é", count: 400))
        #expect(try #require(try store.feature(id: id)).note.unicodeScalars.count <= 280)
    }

    @Test func deletingAFeatureUnlinksItsTasks() throws {
        let store = try store()
        let p = try project(store)
        let f = try store.createFeature(projectID: p, title: "Sign in")
        let t = try store.createTask(projectID: p, title: "Button")
        try store.updateTask(id: t, featureID: .some(f))
        #expect(try store.tasks(projectID: p).first?.featureID == f)
        try store.deleteFeature(id: f)
        #expect(try store.features(projectID: p).isEmpty)
        #expect(try store.tasks(projectID: p).first?.featureID == nil)
        #expect(try store.pending().features.contains { $0.id == f && $0.deletedAt != nil })
    }

    @Test func progressCountsDoneOverAll() throws {
        let store = try store()
        let p = try project(store)
        let a = try store.createFeature(projectID: p, title: "A")
        let b = try store.createFeature(projectID: p, title: "B")
        _ = try store.createFeature(projectID: p, title: "C")
        try store.applyStage(featureID: a, stage: .done, detail: "Merged", prNumber: 4, checkedAt: .now)
        try store.applyStage(featureID: b, stage: .review, detail: "PR #5 open", prNumber: 5, checkedAt: .now)
        let progress = try store.featureProgress(projectID: p)
        #expect(progress.done == 1 && progress.total == 3)
        #expect(progress.counts[.review] == 1 && progress.counts[.planned] == 1)
    }

    @Test func aFeatureCountsItsOwnTasks() throws {
        let store = try store()
        let p = try project(store)
        let f = try store.createFeature(projectID: p, title: "Sign in")
        let a = try store.createTask(projectID: p, title: "A")
        let b = try store.createTask(projectID: p, title: "B", status: .done)
        try store.updateTask(id: a, featureID: .some(f))
        try store.updateTask(id: b, featureID: .some(f))
        let feature = try #require(try store.feature(id: f))
        #expect(feature.openTasks == 1 && feature.doneTasks == 1)
    }

    @Test func anUnchangedStageIsNotAnEdit() throws {
        let store = try store()
        let p = try project(store)
        let f = try store.createFeature(projectID: p, title: "A")
        try store.markSynced(at: .now)
        let changed = try store.applyStage(featureID: f, stage: .planned, detail: "", prNumber: nil, checkedAt: .now)
        #expect(changed == false)
        #expect(try store.pending().features.isEmpty, "an unchanged stage would ping-pong between members")
        #expect(try #require(try store.feature(id: f)).stageCheckedAt != nil)
        #expect(try store.applyStage(featureID: f, stage: .building, detail: "2 commits · 1h ago", prNumber: nil, checkedAt: .now))
        #expect(try store.pending().features.map(\.id) == [f])
    }

    @Test func forgettingAProjectDropsItsFeatures() throws {
        let store = try store()
        let p = try project(store)
        _ = try store.createFeature(projectID: p, title: "A")
        try store.forgetProject(p)
        #expect(try store.features(projectID: p).isEmpty)
        #expect(try store.pending().features.isEmpty)
    }
}
