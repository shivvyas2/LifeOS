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
    var onConnectWhoop: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            AlertBanner(messages: recovery.anomalies.map(Self.message))

            if !recovery.hasAnyReading {
                Button(action: onConnectWhoop) {
                    HStack(spacing: 14) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LifeOSTokens.accent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connect Whoop")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            Text("Recovery, sleep and strain")
                                .font(.system(size: 13))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5),
                                                  lineWidth: 1)
                            }
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                recoveryCard
                sleepCard
            }

            HStack(spacing: 12) {
                PastelFillCard(
                    icon: "waveform.path.ecg",
                    hue: .recovery,
                    label: "HRV",
                    value: recovery.hrvMs.map { "\(Int($0))" },
                    unit: "ms"
                )
                PastelFillCard(
                    icon: "heart.fill",
                    hue: .habits,
                    label: "Resting HR",
                    value: recovery.restingHR.map { "\(Int($0))" },
                    unit: "bpm"
                )
            }

            HStack(spacing: 12) {
                PastelFillCard(
                    icon: "drop.fill",
                    hue: .body,
                    label: "Blood oxygen",
                    value: recovery.spo2Percentage.map { String(format: "%.1f", $0) },
                    unit: "%",
                    caption: recovery.spo2Trend.deltaFromAverage.map { String(format: "%+.1f", $0) }
                )
                PastelFillCard(
                    icon: "thermometer.medium",
                    hue: .activity,
                    label: "Skin temp",
                    value: recovery.skinTempCelsius.map { String(format: "%.1f", $0) },
                    unit: "°C",
                    caption: recovery.skinTempTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }
                )
            }

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

    private var recoveryCard: some View {
        let band = recovery.recoveryPct.map(RecoveryBand.band(for:))
        return PastelFillCard(
            icon: "bolt.heart.fill",
            hue: .nutrition,
            label: "Recovery",
            value: recovery.recoveryPct.map { "\(Int($0))" },
            unit: "%",
            caption: band?.label.uppercased(),
            captionColor: band?.color
        )
    }

    private var sleepCard: some View {
        PastelFillCard(
            icon: "moon.fill",
            hue: .money,
            label: "Sleep",
            split: recovery.sleepMinutes.map(SplitNumeral.sleep(minutes:))
        )
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
            .init(label: "Performance", value: recovery.sleepPerformancePct.map { "\(Int($0))%" }),
            .init(label: "Efficiency", value: recovery.sleepEfficiencyPct.map { "\(Int($0))%" }),
            .init(label: "Consistency", value: recovery.sleepConsistencyPct.map { "\(Int($0))%" }),
            .init(label: "Sleep debt", value: recovery.sleepDebtMinutes.map(Self.duration)),
            .init(label: "7-day average",
                  value: wellness.averageSleepMinutes.map { Self.duration($0) }),
            .init(label: "Verdict", value: wellness.sleepVerdict),
        ]
    }

    private var vitalRows: [StatGroup.Row] {
        [
            .init(label: "Respiratory rate",
                  value: recovery.respiratoryRate.map { String(format: "%.1f", $0) },
                  delta: recovery.respiratoryRateTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
        ]
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
