import SwiftUI
import DesignSystem

/// Recovery for the selected day, and the way into the fortnight behind it.
struct RecoverySection: View {
    let snapshot: RecoverySnapshot

    var body: some View {
        VStack(spacing: 20) {
            if let recovery = snapshot.recoveryPct {
                let band = RecoveryBand.band(for: recovery)
                VStack(spacing: 6) {
                    HeroNumeral(value: "\(Int(recovery))", unit: "%", label: "Recovery")
                        .foregroundStyle(LifeOSTokens.onGradient)
                    // The band is the point. A bare 31 and a bare 81 read alike
                    // at a glance; the colour does not.
                    Text(band.label.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(band.color)
                }
                .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Recovery", reason: "Connect Whoop in Settings")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            }

            StatGroup(title: "Sleep", rows: sleepRows)
            StatGroup(title: "Vitals", rows: vitalRows)
            StatGroup(title: "Day", rows: dayRows)

            if snapshot.hasAnyReading {
                NavigationLink {
                    WhoopDetailScreen(snapshot: snapshot)
                } label: {
                    HStack(spacing: 6) {
                        Text("14-day trends")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(LifeOSTokens.onGradient.opacity(0.16)))
                }
            }

            if let synced = snapshot.syncedAt {
                Text("Synced \(Self.relative.localizedString(for: synced, relativeTo: .now))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LifeOSTokens.onGradient.opacity(0.7))
            }
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var sleepRows: [StatGroup.Row] {
        [
            .init(label: "Duration", value: snapshot.sleepMinutes.map(Self.duration)),
            .init(label: "Performance", value: snapshot.sleepPerformancePct.map { "\(Int($0))%" }),
            .init(label: "Efficiency", value: snapshot.sleepEfficiencyPct.map { "\(Int($0))%" }),
            .init(label: "Consistency", value: snapshot.sleepConsistencyPct.map { "\(Int($0))%" }),
            .init(label: "Sleep debt", value: snapshot.sleepDebtMinutes.map(Self.duration)),
        ]
    }

    /// Every vital carries its distance from the reader's own baseline. Alone
    /// these numbers say nothing: 97.2% blood oxygen is meaningless without
    /// knowing what 97.2 is for this person.
    private var vitalRows: [StatGroup.Row] {
        [
            .init(label: "Blood oxygen",
                  value: snapshot.spo2Percentage.map { String(format: "%.1f%%", $0) },
                  delta: snapshot.spo2Trend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "Skin temp",
                  value: snapshot.skinTempCelsius.map { String(format: "%.1f°C", $0) },
                  delta: snapshot.skinTempTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "Respiratory rate",
                  value: snapshot.respiratoryRate.map { String(format: "%.1f", $0) },
                  delta: snapshot.respiratoryRateTrend.deltaFromAverage
                      .map { String(format: "%+.1f", $0) }),
        ]
    }

    private var dayRows: [StatGroup.Row] {
        [
            .init(label: "Strain", value: snapshot.dayStrain.map { String(format: "%.1f", $0) }),
            .init(label: "HRV", value: snapshot.hrvMs.map { "\(Int($0)) ms" }),
            .init(label: "Resting HR", value: snapshot.restingHR.map { "\(Int($0)) bpm" }),
            .init(label: "Average HR", value: snapshot.averageHR.map { "\(Int($0)) bpm" }),
            .init(label: "Max HR", value: snapshot.maxHR.map { "\(Int($0)) bpm" }),
            .init(label: "Calories", value: snapshot.calories.map { "\(Int($0)) kcal" }),
        ]
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// A titled panel of label and value rows, with an optional baseline delta.
struct StatGroup: View {
    struct Row: Identifiable {
        let label: String
        let value: String?
        var delta: String?
        var id: String { label }
    }

    let title: String
    let rows: [Row]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // A group with nothing in it is not an empty panel, it is absent.
        if rows.contains(where: { $0.value != nil }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .padding(.bottom, 8)

                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        Spacer(minLength: 8)
                        if let delta = row.delta, row.value != nil {
                            Text(delta)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        }
                        Text(row.value ?? "—")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .opacity(row.value == nil ? 0.4 : 1)
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.tileSurface.resolve(scheme))
            )
        }
    }
}

#Preview("Connected") {
    NavigationStack {
        ZStack {
            LinearGradient(colors: [ModuleHue.recovery.top, ModuleHue.recovery.bottom],
                           startPoint: .top, endPoint: .bottom)
            ScrollView {
                RecoverySection(snapshot: RecoverySnapshot(
                    recoveryPct: 72, hrvMs: 62, restingHR: 54, dayStrain: 14.2,
                    sleepMinutes: 432, sleepPerformancePct: 88, sleepEfficiencyPct: 91,
                    sleepConsistencyPct: 70, sleepDebtMinutes: 12,
                    spo2Percentage: 97.2, skinTempCelsius: 33.1, respiratoryRate: 14.2,
                    averageHR: 70, maxHR: 170, calories: 2151, syncedAt: .now
                ))
                .padding()
            }
        }
        .ignoresSafeArea()
    }
}

#Preview("Empty, the real first run") {
    NavigationStack {
        ZStack {
            LinearGradient(colors: [ModuleHue.recovery.top, ModuleHue.recovery.bottom],
                           startPoint: .top, endPoint: .bottom)
            RecoverySection(snapshot: RecoverySnapshot()).padding()
        }
        .ignoresSafeArea()
    }
}
