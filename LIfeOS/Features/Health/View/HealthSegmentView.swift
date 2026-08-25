import SwiftUI
import DesignSystem
import Persistence

/// The Health half: is anything off, then how the body is doing — recovery,
/// sleep, vitals against their own baselines, weight, and the journal.
struct HealthSegmentView: View {
    let recovery: RecoverySnapshot
    let weight: BodySnapshot
    let wellness: WellnessSnapshot
    var onAddJournal: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            AlertBanner(messages: recovery.anomalies.map(Self.message))

            recoveryCard
            StatGroup(title: "Sleep", rows: sleepRows)
            StatGroup(title: "Vitals", rows: vitalRows)
            WeightSection(snapshot: weight)
            journalCard

            if recovery.hasAnyReading {
                NavigationLink {
                    WhoopDetailScreen(snapshot: recovery)
                } label: {
                    HStack(spacing: 6) {
                        Text("14-day trends").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme)))
                }
            }

            if let synced = recovery.syncedAt {
                Text("Synced \(Self.relative.localizedString(for: synced, relativeTo: .now))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
    }

    /// Descriptive, never diagnostic. The banner states the fact and stops.
    static func message(_ finding: AnomalyFinding) -> String {
        let direction = finding.direction == .above ? "well above" : "well below"
        return "\(finding.metric) is \(direction) your 2-week baseline"
    }

    @ViewBuilder
    private var recoveryCard: some View {
        if let pct = recovery.recoveryPct {
            let band = RecoveryBand.band(for: pct)
            SoftCard {
                VStack(spacing: 6) {
                    HeroNumeral(value: "\(Int(pct))", unit: "%", label: "Recovery")
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(band.label.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(band.color)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            HeroEmptyState(label: "Recovery", reason: "Connect Whoop in Settings")
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.top, 18)
        }
    }

    private var journalCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("JOURNAL")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    Spacer()
                    Button(wellness.hasEntryToday ? "Add another" : "Write today") { onAddJournal() }
                        .font(.system(size: 13, weight: .semibold))
                        .tint(LifeOSTokens.accent)
                }
                if wellness.journal.isEmpty {
                    Text("Nothing written yet. How did today feel?")
                        .font(.system(size: 14)).opacity(0.5)
                } else {
                    ForEach(wellness.journal.prefix(4)) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text).font(.system(size: 15)).lineLimit(3)
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.system(size: 12)).opacity(0.45)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
            .init(label: "Duration", value: recovery.sleepMinutes.map(Self.duration)),
            .init(label: "Performance", value: recovery.sleepPerformancePct.map { "\(Int($0))%" }),
            .init(label: "Efficiency", value: recovery.sleepEfficiencyPct.map { "\(Int($0))%" }),
            .init(label: "Consistency", value: recovery.sleepConsistencyPct.map { "\(Int($0))%" }),
            .init(label: "Sleep debt", value: recovery.sleepDebtMinutes.map(Self.duration)),
        ]
    }

    private var vitalRows: [StatGroup.Row] {
        [
            .init(label: "Blood oxygen",
                  value: recovery.spo2Percentage.map { String(format: "%.1f%%", $0) },
                  delta: recovery.spo2Trend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "Skin temp",
                  value: recovery.skinTempCelsius.map { String(format: "%.1f°C", $0) },
                  delta: recovery.skinTempTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "Respiratory rate",
                  value: recovery.respiratoryRate.map { String(format: "%.1f", $0) },
                  delta: recovery.respiratoryRateTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "HRV", value: recovery.hrvMs.map { "\(Int($0)) ms" }),
            .init(label: "Resting HR", value: recovery.restingHR.map { "\(Int($0)) bpm" }),
        ]
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
