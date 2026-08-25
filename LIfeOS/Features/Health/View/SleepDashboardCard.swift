import SwiftUI
import DesignSystem

/// Sleep as structure, not a single duration tile: last night's stages, a
/// week of nights, and duration meters. Glass over the Health canvas.
struct SleepDashboardCard: View {
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    let selectedDate: Date
    private let calendar = Calendar.current
    @Environment(\.colorScheme) private var scheme

    private var night: SleepComposition? {
        recovery.nights.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(spacing: 12) {
            scoresCard
            weekCard
            plansCard
        }
    }

    private var scoresCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sleep scores")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(recovery.sleepPerformancePct.map { "\(Int($0))" } ?? "—")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .opacity(recovery.sleepPerformancePct == nil ? 0.4 : 1)
                        if recovery.sleepPerformancePct != nil {
                            Text("%")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        }
                    }
                }

                if let night, !night.scoreBarSegments.isEmpty {
                    SleepStageBar(segments: night.scoreBarSegments, height: 18)
                } else if recovery.sleepMinutes != nil {
                    Text("Stages not recorded for this night")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                if !detailChips.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(detailChips, id: \.label) { chip in
                            VStack(spacing: 2) {
                                Text(chip.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                Text(chip.value)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(SleepComposition.Stage.rem.color.opacity(0.12))
                            )
                        }
                    }
                }

                if let verdict = wellness.sleepVerdict {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(verdict)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.12, green: 0.68, blue: 0.64))
                    )
                }
            }
        }
    }

    private var weekCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("This week")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { day in
                        let night = night(on: day)
                        VStack(spacing: 6) {
                            Circle()
                                .fill(night.map(Self.stageColor(for:))
                                      ?? LifeOSTokens.primaryText.resolve(scheme).opacity(0.08))
                                .frame(width: 28, height: 28)
                            Text(day, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            Text(day, format: .dateTime.day())
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var plansCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sleep duration")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                durationRow(
                    title: recovery.sleepMinutes.map(Self.duration) ?? "—",
                    subtitle: "Total sleep",
                    minutes: recovery.sleepMinutes,
                    scale: 480,
                    color: SleepComposition.Stage.rem.color
                )

                durationRow(
                    title: recovery.napMinutes.map(Self.duration) ?? "None",
                    subtitle: "Nap duration",
                    minutes: recovery.napMinutes,
                    scale: 90,
                    color: SleepComposition.Stage.light.color
                )
            }
        }
    }

    private func durationRow(title: String, subtitle: String, minutes: Int?,
                             scale: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .opacity(minutes == nil ? 0.45 : 1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            Spacer(minLength: 8)
            BlockMeter(filled: blocks(minutes: minutes, scale: scale), color: color)
        }
    }

    private var detailChips: [(label: String, value: String)] {
        var chips: [(label: String, value: String)] = []
        if let efficiency = recovery.sleepEfficiencyPct {
            chips.append(("Efficiency", "\(Int(efficiency))%"))
        }
        if let consistency = recovery.sleepConsistencyPct {
            chips.append(("Consistency", "\(Int(consistency))%"))
        }
        if let debt = recovery.sleepDebtMinutes {
            chips.append(("Debt", Self.duration(debt)))
        }
        return chips
    }

    private var weekDays: [Date] {
        let start = calendar.date(byAdding: .day, value: -6,
                                  to: calendar.startOfDay(for: selectedDate))
            ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func night(on day: Date) -> SleepComposition? {
        recovery.nights.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private static func stageColor(for night: SleepComposition) -> Color {
        night.scoreBarSegments.max(by: { $0.minutes < $1.minutes })?.stage.color
            ?? SleepComposition.Stage.rem.color
    }

    private func blocks(minutes: Int?, scale: Int) -> Int {
        guard let minutes, scale > 0 else { return 0 }
        return min(10, Int((Double(minutes) / Double(scale) * 10).rounded()))
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct BlockMeter: View {
    let filled: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index < filled ? color : Color.primary.opacity(0.10))
                    .frame(width: 11, height: 12)
            }
        }
    }
}
