import SwiftUI
import DesignSystem

/// A night's duration, stage composition and recorded quality measures.
struct SleepDashboardCard: View {
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    let selectedDate: Date
    @Environment(\.colorScheme) private var scheme

    private var night: SleepComposition? {
        recovery.nights.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        SoftCard(hue: .nutrition) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Sleep", systemImage: "moon").font(.headline)
                    Spacer()
                    Text(selectedDate.formatted(.dateTime.month().day()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(recovery.sleepMinutes.map(Self.duration) ?? "Not recorded")
                    .font(.largeTitle.bold()).monospacedDigit()
                if let night, !night.segments.isEmpty {
                    SleepStageBar(segments: night.segments, height: 16, showsLabels: false)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], alignment: .leading, spacing: 12) {
                        ForEach(night.segments) { segment in
                            HStack(spacing: 6) {
                                Circle().fill(segment.stage.color).frame(width: 6, height: 6)
                                Text(segment.stage.label).foregroundStyle(.secondary)
                                Text(Self.duration(segment.minutes)).monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    Text("Sleep stages weren’t recorded for this night.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    qualityRow("Performance", value: recovery.sleepPerformancePct.map { "\(Int($0))%" })
                    qualityRow("Efficiency", value: recovery.sleepEfficiencyPct.map { "\(Int($0))%" })
                    qualityRow("Consistency", value: recovery.sleepConsistencyPct.map { "\(Int($0))%" })
                    qualityRow("Sleep debt", value: recovery.sleepDebtMinutes.map(Self.duration))
                    qualityRow("Naps", value: recovery.napMinutes.map(Self.duration))
                }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        }
    }

    @ViewBuilder private func qualityRow(_ label: String, value: String?) -> some View {
        if let value {
            Divider()
            HStack {
                Text(label).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                Spacer()
                Text(value).monospacedDigit()
            }
            .font(.subheadline).padding(.vertical, 12)
        }
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
