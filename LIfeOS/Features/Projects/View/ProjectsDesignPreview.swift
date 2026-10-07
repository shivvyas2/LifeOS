#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// Projects without a server: `--page=projects`, `project-board`,
/// `project-schedule`, `project-milestones`, `project-list`, `project-task`.
struct ProjectsDesignPreview: View {
    let page: String
    @State private var fixture = ProjectsFixture()

    var body: some View {
        NavigationStack {
            switch page {
            case "project-board": ProjectScreen(model: fixture.model, projectID: fixture.launch, initialPane: .board)
            case "project-schedule": ProjectScreen(model: fixture.model, projectID: fixture.launch, initialPane: .schedule)
            case "project-milestones": ProjectScreen(model: fixture.model, projectID: fixture.launch, initialPane: .milestones)
            case "project-list": ProjectScreen(model: fixture.model, projectID: fixture.launch, initialPane: .list)
            case "project-task":
                ProjectScreen(model: fixture.model, projectID: fixture.launch)
                    .sheet(isPresented: .constant(true)) {
                        TaskSheet(model: fixture.model, projectID: fixture.launch, target: .task(fixture.wireframes),
                                  members: (try? fixture.model.store?.members(projectID: fixture.launch)) ?? [],
                                  milestones: (try? fixture.model.store?.milestones(projectID: fixture.launch)) ?? [])
                    }
            default: ProjectsHomeScreen(model: fixture.model)
            }
        }
        .modelContainer(fixture.container)
    }
}

@MainActor
private final class ProjectsFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let model = ProjectsViewModel()
    let me = UUID()
    let launch: UUID
    let wireframes: UUID

    init() {
        let context = container.mainContext
        model.attach(context, sync: nil, me: me)
        let store = ProjectsStore(context: context)
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        }
        launch = try! store.createProject(name: "LifeOS 1.1", scope: "Ship Notes, Today layout and the GitHub card",
                                          colour: "tomato", ownerID: me, startsOn: today,
                                          endsOn: Calendar.current.date(byAdding: .day, value: 21, to: today))
        let design = try! store.createProject(name: "Portfolio site", scope: "Case studies and a contact form",
                                              colour: "lagoon", ownerID: me)
        let alpha = try! store.createMilestone(projectID: launch, title: "Alpha", dueOn: today.addingTimeInterval(5 * 86_400))
        let beta = try! store.createMilestone(projectID: launch, title: "Beta", dueOn: today.addingTimeInterval(14 * 86_400))
        wireframes = try! store.createTask(projectID: launch, title: "Wireframing and brainstorming")
        try! store.updateTask(id: wireframes, notes: "Simplify the login flow; tighten the sidebar.", ownerID: .some(me),
                              milestoneID: .some(alpha), startsAt: .some(at(9, 15)), endsAt: .some(at(10, 15)))
        try! store.moveTask(id: wireframes, to: .doing, at: 0)
        let system = try! store.createTask(projectID: launch, title: "Design system planning")
        try! store.updateTask(id: system, ownerID: .some(me), milestoneID: .some(alpha),
                              startsAt: .some(at(11, 15)), endsAt: .some(at(13)))
        let explore = try! store.createTask(projectID: launch, title: "Exploration phase")
        try! store.updateTask(id: explore, milestoneID: .some(beta), startsAt: .some(at(12)), endsAt: .some(at(14)))
        let review = try! store.createTask(projectID: launch, title: "Client review", status: .done)
        try! store.updateTask(id: review, milestoneID: .some(alpha))
        _ = try! store.createTask(projectID: launch, title: "Release notes")
        let copy = try! store.createTask(projectID: design, title: "Write the case studies")
        try! store.updateTask(id: copy, ownerID: .some(me), dueOn: .some(today))
        _ = try! store.createTask(projectID: design, title: "Contact form", status: .done)
        // A year of finished work, for the grid.
        for offset in 0..<200 where offset % 3 != 0 {
            let id = try! store.createTask(projectID: design, title: "Done \(offset)", status: .done)
            let record = try! context.fetch(FetchDescriptor<ProjectTaskRecord>()).first { $0.id == id }!
            record.doneAt = today.addingTimeInterval(-Double(offset) * 86_400)
            if offset % 7 == 0 { _ = try! store.createTask(projectID: design, title: "Done extra \(offset)", status: .done) }
        }
        try! context.save()
        model.load()
    }
}
#endif
