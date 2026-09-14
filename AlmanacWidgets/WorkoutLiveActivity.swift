import ActivityKit
import SwiftUI
import WidgetKit
import AppSurfaces

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.attributes.icon)
                    .font(.title).foregroundStyle(.orange)
                    .frame(width: 52, height: 52).background(.orange.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.name).font(.headline)
                    Text(context.state.runningSince == nil ? "Paused" : "In progress")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                workoutTimer(context.state).font(.system(.title2, design: .rounded, weight: .bold)).minimumScaleFactor(0.8).frame(width: 90)
            }
            .padding(20)
            .activityBackgroundTint(Color(white: 0.12))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(SurfaceRoute.activity.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.name, systemImage: context.attributes.icon).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    workoutTimer(context.state).font(.title2.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.runningSince == nil ? "Paused" : "In progress").foregroundStyle(.secondary)
                        Spacer()
                        Link("Open activity →", destination: SurfaceRoute.activity.url).foregroundStyle(.orange)
                    }.font(.subheadline).padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: context.attributes.icon).foregroundStyle(.orange)
            } compactTrailing: {
                workoutTimer(context.state).font(.caption2).frame(width: 48)
            } minimal: {
                Image(systemName: context.state.runningSince == nil ? "pause.fill" : context.attributes.icon).foregroundStyle(.orange)
            }
            .widgetURL(SurfaceRoute.activity.url)
            .keylineTint(.orange)
        }
    }
    @ViewBuilder private func workoutTimer(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let anchor = state.timerAnchor {
            Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
                .monospacedDigit().contentTransition(.numericText()).privacySensitive()
        } else {
            Text(Duration.seconds(state.elapsed).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit().privacySensitive()
        }
    }
}
