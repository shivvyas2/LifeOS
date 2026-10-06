import Testing
import Foundation
@testable import Persistence

@Suite struct NoteSnapshotTests {
    private func folder(_ name: String, bucket: NoteBucket, children: [NoteFolderSnapshot] = []) -> NoteFolderSnapshot {
        NoteFolderSnapshot(id: UUID(), name: name, icon: "", accent: .sage, bucket: bucket, parentID: nil, count: 0, children: children)
    }

    @Test func moveTargetsWalkNestedFoldersShelvesFirst() {
        let drills = folder("Drills", bucket: .projects)
        let training = folder("Training", bucket: .projects, children: [drills])
        let snapshot = NotesSnapshot(folders: [.projects: [training], .areas: [folder("Home", bucket: .areas)]])

        let targets = snapshot.moveTargets()

        #expect(targets.map(\.title) == ["Projects", "Training", "Training / Drills", "Areas", "Home", "Research"])
        #expect(targets.map(\.depth) == [0, 1, 2, 0, 1, 0])
        #expect(targets[2].folderID == drills.id && targets[2].bucket == .projects)
        #expect(targets[0].folderID == nil)
        #expect(!targets.contains { $0.bucket == .archive })
    }
}
