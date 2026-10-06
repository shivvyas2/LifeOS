import SwiftUI
import UIKit
import AppSurfaces
import DesignSystem
import Persistence

/// The weather card: the feels-like high as the figure, the condition, three
/// quiet lines, and the Wear line on a row. Or what stands in for it until
/// location is allowed.
struct WeatherCard: View {
    let state: WeatherState
    let isToday: Bool
    var onAllowLocation: () -> Void
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .needsLocation:
                notice("Weather needs your location.", action: "Allow location", onAction: onAllowLocation)
            case .denied:
                notice("Turn location on in Settings for weather.", action: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .loading:
                Text("Reading the sky…").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    .editorialCard()
            case .unavailable:
                Text("No forecast right now.").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
                    .editorialCard()
            case .ready(let forecast):
                card(forecast)
            }
        }
    }

    private func notice(_ sentence: String, action: String, onAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(sentence).font(LifeOSType.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action, action: onAction).buttonStyle(.editorial(.primary, size: .compact))
        }
        .editorialCard()
    }

    private func card(_ forecast: DayForecast) -> some View {
        let quiet = Editorial.quietInk(scheme)
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        let wear = WearText.line(
            feelsLikeHighC: forecast.feelsLikeHighC, feelsLikeLowC: forecast.feelsLikeLowC,
            rainChanceByHour: forecast.rainChanceByHour, windKph: forecast.windKph, uvIndex: forecast.uvIndex,
            currentHour: isToday ? calendar.component(.hour, from: .now) : nil
        )
        return VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .top, spacing: Space.x2) {
                VStack(alignment: .leading, spacing: Space.half) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Self.degrees(forecast.feelsLikeHighC))
                            .font(Editorial.figure(64)).tracking(Editorial.figureTracking(64)).monospacedDigit()
                        Text("°").font(Editorial.figure(28))
                    }
                    .foregroundStyle(ink)
                    HStack(spacing: Space.half) {
                        Image(systemName: forecast.conditionSymbol)
                        Text(forecast.conditionName)
                    }
                    .font(LifeOSType.secondary).foregroundStyle(quiet)
                }
                Spacer(minLength: Space.x1)
                VStack(alignment: .trailing, spacing: Space.half) {
                    Text("High \(Self.degrees(forecast.highC))° · Low \(Self.degrees(forecast.lowC))°")
                    Text(rainLine(forecast))
                    Text("Wind \(Self.speed(forecast.windKph)) · UV \(forecast.uvIndex)")
                }
                .font(LifeOSType.caption).foregroundStyle(quiet).multilineTextAlignment(.trailing)
            }
            EditorialRow("Wear", value: wear)
        }
        .editorialCard()
        .accessibilityElement(children: .combine)
    }

    private func rainLine(_ forecast: DayForecast) -> String {
        guard let wet = WearText.firstWetHour(forecast.rainChanceByHour) else { return "No rain expected" }
        let chance = Int((forecast.rainChanceByHour[wet] * 100).rounded())
        return "Rain \(chance)% from \(WearText.hourText(wet, calendar: calendar, locale: .current))"
    }

    /// Celsius in, the device's unit out, digits only; the sign is drawn beside.
    static func degrees(_ celsius: Double, digits: Int = 0) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let value = measurement.converted(to: UnitTemperature(forLocale: .current)).value
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func speed(_ kph: Double) -> String {
        Measurement(value: kph, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// The checklist: a square, the text, a quiet detail, hairlines between.
/// Ticking is a tap on the square; the text opens the page or the habits.
struct ChecklistRows: View {
    let rows: [ChecklistRow]
    var onTick: (ChecklistRow) -> Void
    var onOpen: (ChecklistRow) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Button { onTick(row) } label: {
                        Image(systemName: row.isDone ? "checkmark.square.fill" : "square")
                            .font(LifeOSType.body)
                            .foregroundStyle(row.isDone ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.isEditable)
                    .accessibilityLabel(row.isEditable
                        ? "\(row.text), \(row.isDone ? "done" : "not done"), double tap to \(row.isDone ? "untick" : "tick")"
                        : "\(row.text), \(row.isDone ? "done" : "not done")")
                    Button { onOpen(row) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                            Text(row.text)
                                .font(LifeOSType.body)
                                .strikethrough(row.isDone)
                                .foregroundStyle(row.isDone ? Editorial.quietInk(scheme) : LifeOSTokens.primaryText.resolve(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = row.detail {
                                Text(detail).font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(openHint(row))
                }
                .padding(.vertical, 10)
                Hairline()
            }
        }
    }

    private func openHint(_ row: ChecklistRow) -> String {
        switch row.source {
        case .habit: "Opens habits"
        default: "Opens the page"
        }
    }
}

/// Readings against their targets. Whole hours read as `8h`, not `8h 0m`.
struct ReadingsRows: View {
    let readings: DayReadings
    let workouts: [DayWorkout]

    var body: some View {
        EditorialRow("Steps", value: readings.steps.map { "\($0.formatted()) of \(readings.stepsTarget.formatted())" } ?? "No reading")
        EditorialRow("Sleep", value: readings.sleepMinutes.map { "\(Self.duration($0)) of \(Self.duration(readings.sleepTargetMinutes))" } ?? "No reading")
        EditorialRow("Weight", value: readings.weightKg.map { String(format: "%.1f kg", $0) } ?? "No reading")
        EditorialRow("Recovery", value: readings.recoveryPct.map { "\(Int($0.rounded()))%" } ?? "No reading")
        ForEach(workouts) { workout in
            EditorialRow(workout.title, value: Self.duration(workout.durationMinutes))
        }
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}

/// The day's spend as a figure, then up to three rows, cents exact.
struct SpendRows: View {
    let spend: DaySpending
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if spend.rows.isEmpty {
            Text("Nothing spent").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
        } else {
            EditorialFigure(label: "Spent", value: spend.total.formatted(.currency(code: "USD").precision(.fractionLength(2))), size: 44)
            ForEach(spend.rows) { row in
                EditorialRow(row.merchant, value: abs(row.amount).formatted(.currency(code: "USD").precision(.fractionLength(2))))
            }
        }
    }
}

/// That day's nudges from LIFO, text and time.
struct NudgeRows: View {
    let nudges: [InboxEntry]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if nudges.isEmpty {
            Text("Nothing from LIFO").font(LifeOSType.secondary).foregroundStyle(Editorial.quietInk(scheme))
        } else {
            ForEach(nudges) { nudge in
                EditorialRow(nudge.receivedAt.formatted(.dateTime.hour().minute())) {
                    Text(nudge.text).lineLimit(3)
                }
            }
        }
    }
}
