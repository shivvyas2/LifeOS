import SwiftUI
import DesignSystem
import Persistence
import Integrations

/// Each module Today can show, drawn from the pieces Today already had and
/// the day screen's rows.
extension TodayScreen {
    @ViewBuilder
    func rowView(_ row: TodayRow) -> some View {
        switch row {
        case .single(let module):
            moduleView(module)
        case .pair(let first, let second):
            // A lone tile keeps half the width, so a tile reads as a tile.
            HStack(alignment: .top, spacing: 12) {
                tileButton(first)
                if let second { tileButton(second) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
        }
    }

    @ViewBuilder
    func moduleView(_ module: TodayModule) -> some View {
        switch module {
        case .nextUp: agendaCard
        case .month: month
        case .tasks: tasksModule
        case .github: githubModule
        case .scheduledWorkout:
            if snapshot.scheduledWorkoutTitle != nil { scheduledWorkout } else { ghost(module, note: "Nothing scheduled") }
        case .steps, .sleep, .weight, .recovery: tileButton(module)
        case .weather:
            WeatherCard(state: day.briefing?.weather ?? .loading, isToday: true) {
                Task { await day.allowLocation() }
            }
        case .spentToday: spendModule
        case .projects: projectsModule
        case .inbox: inboxModule
        case .fromLifo:
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(title: "From LIFO")
                NudgeRows(nudges: day.briefing?.nudges ?? [])
            }
        }
    }

    /// A module with nothing to show is drawn only while arranging, so it can
    /// still be moved or hidden.
    @ViewBuilder
    func ghost(_ module: TodayModule, note: String, action: (String, () -> Void)? = nil) -> some View {
        if store.isArranging {
            VStack(alignment: .leading, spacing: Space.half) {
                Text(module.title).font(LifeOSType.rowTitle)
                Text(note).font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                if let action {
                    Button(action.0, action: action.1).buttonStyle(.editorial(.secondary, size: .compact))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialCard()
        }
    }

    func tileButton(_ module: TodayModule) -> some View {
        let metric = TodayMetric(module: module)
        return Button { if !store.isArranging { onSelectMetric(metric) } } label: { tile(metric) }
            .buttonStyle(.plain)
            .opacity(showsHealthPrompt ? 0.35 : 1)
            .allowsHitTesting(!showsHealthPrompt)
            .accessibilityHidden(showsHealthPrompt)
            .accessibilityLabel(accessibilityLabel(metric))
            .accessibilityHint("Opens \(metric.title.lowercased()) history")
            .frame(maxWidth: .infinity)
    }

    private var tasksModule: some View {
        let rows = day.briefing?.checklist ?? []
        return VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Today's tasks") {
                if !rows.isEmpty {
                    Text("\(rows.filter(\.isDone).count) of \(rows.count)")
                        .font(LifeOSType.label).monospacedDigit().foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            if rows.isEmpty {
                Text("Nothing planned. Add a task below.")
                    .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
            }
            // A row's text opens today's day screen, which opens pages.
            // Checked as well as hit-testing: a long-press that starts arranging
            // can still release onto a row, and VoiceOver ignores hit-testing.
            ChecklistRows(rows: rows,
                          onTick: { if !store.isArranging { day.tick($0) } },
                          onOpen: { _ in if !store.isArranging { onOpenToday() } })
            HairlineField(text: $newTask, placeholder: "Add a task", glyph: "plus", submitLabel: .done,
                          focus: $taskFieldFocused,
                          onSubmit: {
                              // The text stays if the write failed, so nothing typed is lost.
                              if day.add(newTask) { newTask = "" }
                          })
        }
    }

    @ViewBuilder
    private var githubModule: some View {
        if let project = day.briefing?.project {
            VStack(alignment: .leading, spacing: Space.x2) {
                EditorialSectionHeader(title: "Project") {
                    if case .card(let card, _) = project {
                        Button(card.repo) { openURL(card.repoURL) }
                            .buttonStyle(.plain).font(LifeOSType.label).foregroundStyle(Editorial.quietInk(scheme))
                    }
                }
                ProjectRows(state: project, onOpen: { openURL($0) }, onReconnect: onOpenSettings)
            }
        } else if case .connected = github?.state {
            ghost(.github, note: "No commits yet today")
        } else {
            ghost(.github, note: "Not connected", action: ("Connect GitHub", onOpenSettings))
        }
    }

    /// Hidden outside arranging until Gmail is connected.
    @ViewBuilder
    private var inboxModule: some View {
        if let source = mailSource, source.isConnected {
            InboxRows(state: inbox ?? .loading, onReconnect: onOpenSettings)
        } else {
            ghost(.inbox, note: "Not connected", action: ("Connect Gmail", onOpenSettings))
        }
    }

    /// The last twelve weeks of finished project work and the three active
    /// projects' progress; a tap opens the Projects tab.
    @ViewBuilder
    private var projectsModule: some View {
        let store = ProjectsStore(context: context)
        let projects = Array(((try? store.projects()) ?? []).prefix(3))
        Button { if !self.store.isArranging { onOpenProjects() } } label: {
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack {
                    Text("PROJECTS").brutalLabel()
                    Spacer()
                    Image(systemName: "arrow.right").font(LifeOSType.label.weight(.heavy))
                }
                ContributionGrid(counts: (try? store.completedPerDay(endingOn: .now, days: 84)) ?? [],
                                 colour: .moss, weeks: 12)
                if projects.isEmpty {
                    Text("No projects yet.").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                }
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(project.name.uppercased()).font(LifeOSType.label.weight(.heavy))
                        BrutalProgress(fraction: project.fraction, colour: ProjectColour(named: project.colour))
                    }
                }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .brutalCard()
        }
        .buttonStyle(.plain)
    }

    private var spendModule: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Spent today")
            if let spend = day.briefing?.spend {
                SpendRows(spend: spend)
            } else {
                Text("Nothing spent").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
            }
        }
    }
}

extension TodayMetric {
    /// The tile a stat module draws.
    init(module: TodayModule) {
        switch module {
        case .sleep: self = .sleep
        case .weight: self = .weight
        case .recovery: self = .recovery
        default: self = .steps
        }
    }
}
