import SwiftUI
import DesignSystem
import Persistence

/// A project's features in plan order with their stages, and how many are
/// done. Set in the app's editorial style (paper cards, hairlines, numbered
/// sections) rather than the tab's hard-edged blocks, so the plan reads like
/// the rest of the app. `header` takes the GitHub "as of" line; `footer`
/// takes the Draft button.
struct ProjectPlanView<Header: View, Footer: View>: View {
    let features: [FeatureSnapshot]
    let progress: FeatureProgress
    @ViewBuilder var header: () -> Header
    let onOpen: (UUID) -> Void
    let onAdd: (String) -> Void
    let onMove: (UUID, Int) -> Void
    let onDelete: (UUID) -> Void
    @ViewBuilder var footer: () -> Footer

    @Environment(\.colorScheme) private var scheme
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x2) {
                if progress.total > 0 {
                    Text("\(progress.done) OF \(progress.total) FEATURES DONE").editorialEyebrow()
                    EditorialProgressBar(fraction: progress.fraction)
                    HStack(spacing: Space.x3) {
                        ForEach(FeatureStage.allCases, id: \.self) { stage in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(progress.counts[stage] ?? 0)")
                                    .font(Editorial.figure(28)).monospacedDigit()
                                Text(stage.title).font(LifeOSType.caption)
                                    .foregroundStyle(Editorial.quietInk(scheme))
                            }
                        }
                    }
                } else {
                    Text("No features yet").editorialEyebrow()
                    Text("List what this project needs to ship, in the order you will build it.")
                        .font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                }
                header()
            }
            .editorialCard()

            VStack(alignment: .leading, spacing: 0) {
                EditorialSectionHeader(index: 1, title: "Features")
                ForEach(Array(features.enumerated()), id: \.element.id) { offset, feature in
                    Button { onOpen(feature.id) } label: { FeatureRow(feature: feature) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(feature.title)
                        .accessibilityAction(named: "Move up") { onMove(feature.id, max(feature.position - 1, 0)) }
                        .accessibilityAction(named: "Move down") { onMove(feature.id, feature.position + 1) }
                        .contextMenu {
                            Button("Move up") { onMove(feature.id, max(feature.position - 1, 0)) }
                            Button("Move down") { onMove(feature.id, feature.position + 1) }
                            Button("Delete", role: .destructive) { onDelete(feature.id) }
                        }
                    if offset < features.count - 1 { Hairline() }
                }
                HStack(spacing: Space.x2) {
                    TextField("New feature", text: $newTitle)
                        .font(LifeOSType.body)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.editorial(.secondary, size: .compact))
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, Space.x2)
            }

            footer()
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAdd(title)
        newTitle = ""
    }
}

/// One feature: title, the line under it, and its stage.
struct FeatureRow: View {
    let feature: FeatureSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(LifeOSType.rowTitle)
                if !feature.stageDetail.isEmpty {
                    Text(feature.stageDetail).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            Spacer()
            StageTag(stage: feature.stage)
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .padding(.vertical, Space.x2)
        .contentShape(.rect)
    }
}

/// The stage as an outlined tag. Never filled: the filled tag is the accent,
/// which the app keeps for things that are live or urgent.
struct StageTag: View {
    let stage: FeatureStage
    var body: some View {
        EditorialTag(stage == .done ? "✓ \(stage.label)" : stage.label)
            .accessibilityLabel(stage.label)
    }
}

/// A thin ink bar on a hairline track: the editorial counterpart of the
/// tab's block progress.
struct EditorialProgressBar: View {
    let fraction: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Editorial.rule(scheme))
                Capsule().fill(LifeOSTokens.primaryText.resolve(scheme))
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

extension FeatureStage {
    /// Sentence case, for the counts under the bar.
    var title: String {
        switch self {
        case .planned: "Planned"
        case .building: "Building"
        case .review: "In review"
        case .done: "Done"
        }
    }
}
