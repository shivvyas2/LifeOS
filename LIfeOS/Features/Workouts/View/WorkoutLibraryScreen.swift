import SwiftUI
import DesignSystem
import Persistence
import Sectors

/// Today's session, then the catalog filtered to it.
///
/// Pushed from the Fitness segment's training card and from Begin Activity,
/// on whichever stack the person is already on, so the way back is the way
/// they came.
struct WorkoutLibraryScreen: View {
    @Bindable var model: WorkoutLibraryViewModel
    /// The player needs the live recorder, and the library is pushed on two
    /// different stacks, so it is handed down rather than reached for.
    var recorder: ActivityRecorder
    /// Handed the tapped video when a caller wants the push for itself. Nil,
    /// which is what both entry points pass today, means this screen opens
    /// the player on its own stack.
    var onOpen: ((CatalogVideo) -> Void)?

    @State private var opened: CatalogVideo?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout

    var body: some View {
        GradientCanvas(hue: .activity) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    todayCard
                    // When there is nothing to list, the empty card carries
                    // the same sentence; saying it twice would read as two
                    // different problems.
                    if !model.filtered.isEmpty, let status = model.status {
                        Label(status, systemImage: "info.circle")
                            .font(LifeOSType.caption)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    filters
                    if model.filtered.isEmpty { emptyState } else { list }
                }
                .frame(maxWidth: layout.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.gutter)
                .padding(.top, 8)
                .padding(.bottom, layout.contentBottomInset)
            }
            .refreshable { await model.refreshIfDue(force: true) }
        }
        .navigationTitle("Workout library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Training preferences", systemImage: "slider.horizontal.3") {
                    model.needsPreferences = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $model.needsPreferences) { TrainingPreferencesSheet(model: model) }
        .navigationDestination(item: $opened) { video in
            VideoWorkoutScreen(video: video, model: recorder)
        }
        .task { await model.refreshIfDue() }
        .tint(LifeOSTokens.accent)
    }

    private var todayCard: some View {
        SoftCard(hue: .activity) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY")
                    .font(LifeOSType.eyebrow).tracking(0.6).opacity(0.55)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.plan.map { "\($0.split.capitalized) day" } ?? "No plan yet")
                        .font(LifeOSType.sectionTitle)
                    Spacer(minLength: 8)
                    if let minutes = model.plan?.minutes {
                        Text("\(minutes) min")
                            .font(LifeOSType.label)
                            .foregroundStyle(LifeOSTokens.accent)
                    }
                }
                if let reason = model.plan?.reason {
                    Text(reason).font(LifeOSType.secondary)
                }
                Text(model.batteryLine ?? "Battery unknown · a cautious target")
                    .font(LifeOSType.caption.weight(.medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.splitOptions, id: \.self) { split in
                    chip(split.capitalized, selected: (model.splitFilter ?? model.plan?.split) == split) {
                        model.splitFilter = model.splitFilter == split ? nil : split
                    }
                }
                Divider().frame(height: 22)
                ForEach(DurationBand.allCases, id: \.self) { band in
                    chip(band.title, selected: model.durationBand == band) {
                        model.durationBand = model.durationBand == band ? nil : band
                    }
                }
                if !model.equipmentOptions.isEmpty {
                    Divider().frame(height: 22)
                    ForEach(model.equipmentOptions, id: \.self) { item in
                        chip(item.capitalized, selected: model.equipmentFilter == item) {
                            model.equipmentFilter = model.equipmentFilter == item ? nil : item
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LifeOSType.label)
                .foregroundStyle(selected ? Color.white : LifeOSTokens.primaryText.resolve(scheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? AnyShapeStyle(LifeOSTokens.accent)
                                     : AnyShapeStyle(LifeOSTokens.cardSurface.resolve(scheme)),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var list: some View {
        LazyVStack(spacing: 12) {
            ForEach(model.filtered) { video in
                WorkoutVideoRow(video: video) {
                    if let onOpen { onOpen(video) } else { opened = video }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: model.videos.isEmpty ? "wifi.slash" : "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Text(model.status ?? (model.videos.isEmpty
                 ? "The library needs a connection the first time."
                 : "Nothing in the catalog matches these filters yet."))
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Text(model.videos.isEmpty
                 ? "Once it has downloaded, every session is here offline."
                 : "Clear a chip to see more of the catalog.")
                .font(LifeOSType.caption)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
    }
}
