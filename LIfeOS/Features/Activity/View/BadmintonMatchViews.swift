import SwiftUI
import DesignSystem
import AppSurfaces
import Integrations

/// How the next badminton workout is set up, chosen before Start.
///
/// Edits write straight through to the recorder's remembered setup, so the
/// card needs no Save button and the same partner and opponents are already
/// filled in next week.
struct BadmintonSetupCard: View {
    @Binding var setup: BadmintonSession?
    @State private var kind: BadmintonSession.Kind = .match
    @State private var format: BadmintonSession.Format = .singles
    @State private var teammate = ""
    @State private var opponentOne = ""
    @State private var opponentTwo = ""
    @State private var focus = ""
    @State private var loaded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(index: 1, title: "Today on court")
            Picker("Session", selection: $kind) {
                Text("Match").tag(BadmintonSession.Kind.match)
                Text("Practice").tag(BadmintonSession.Kind.practice)
            }
            .pickerStyle(.segmented)

            if kind == .match {
                Picker("Format", selection: $format) {
                    Text("Singles").tag(BadmintonSession.Format.singles)
                    Text("Doubles").tag(BadmintonSession.Format.doubles)
                }
                .pickerStyle(.segmented)
                if format == .doubles {
                    field("Your partner", text: $teammate)
                }
                field(format == .doubles ? "Opponent one" : "Opponent", text: $opponentOne)
                if format == .doubles {
                    field("Opponent two", text: $opponentTwo)
                }
                Text("Score each rally from the watch or here. Names are optional.")
                    .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            } else {
                field("What are you working on?", text: $focus)
                Text("Practice is recorded without a score.")
                    .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
        }
        .onAppear(perform: load)
        .onChange(of: [kind.rawValue, format.rawValue, teammate, opponentOne, opponentTwo, focus]) { _, _ in
            guard loaded else { return }
            setup = BadmintonSession(kind: kind, format: format, teammate: teammate,
                                     opponents: [opponentOne, opponentTwo], focus: focus)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(title, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(LifeOSType.body)
                .frame(minHeight: 44)
            Hairline()
        }
    }

    private func load() {
        defer { loaded = true }
        guard !loaded else { return }
        if let setup {
            kind = setup.kind; format = setup.format
            teammate = setup.teammate ?? ""
            opponentOne = setup.opponents.first ?? ""
            opponentTwo = setup.opponents.dropFirst().first ?? ""
            focus = setup.focus ?? ""
        } else {
            // Showing the card is choosing badminton; a match is the default.
            setup = BadmintonSession()
        }
    }
}

/// The live scoreboard on the phone, for a badminton match in progress.
struct BadmintonScoreCard: View {
    let model: ActivityRecorder
    @Environment(\.colorScheme) private var scheme

    private var session: BadmintonSession { model.badminton ?? BadmintonSession() }
    private var score: BadmintonScore { session.score ?? BadmintonScore() }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(index: 1, title: score.isOver ? "Final score" : "Score") {
                Button { model.undoRally() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(LifeOSType.label.weight(.semibold)).frame(minHeight: 44)
                }
                .disabled(score.rallies.isEmpty)
                .accessibilityLabel("Undo last point")
            }
            if score.isOver {
                Text(score.winner == .us ? "Match won" : "Match lost")
                    .font(Editorial.headline(28))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            } else {
                HStack(spacing: Space.x1) {
                    side(.us, name: usName)
                    side(.them, name: themName)
                }
                Text(serveLine).font(LifeOSType.caption)
                    .foregroundStyle(score.changesEndsNow ? LifeOSTokens.accent : Editorial.quietInk(scheme))
            }
            if !score.games.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(score.games.enumerated()), id: \.offset) { index, game in
                        EditorialRow("Game \(index + 1)", value: "\(game.us) – \(game.them)")
                    }
                }
            }
            if model.source == .watch {
                Text("Your watch keeps the score; taps here go to it.")
                    .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
        }
    }

    private var usName: String { session.teammate.map { "You & \($0)" } ?? "You" }
    private var themName: String {
        session.opponents.isEmpty ? "Them" : session.opponents.joined(separator: " & ")
    }

    private var serveLine: String {
        if score.changesEndsNow { return "Change ends at 11" }
        let who = score.server == .us ? "You serve" : "They serve"
        return "\(who) from the \(score.serviceCourt == .right ? "right" : "left")"
    }

    /// One side's half: the button that awards that side the rally.
    private func side(_ side: BadmintonSide, name: String) -> some View {
        let serving = score.server == side
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        return Button { model.scoreRally(side) } label: {
            VStack(alignment: .leading, spacing: Space.half) {
                HStack(spacing: 6) {
                    if serving { Circle().fill(LifeOSTokens.accent).frame(width: 8, height: 8) }
                    Text(name).font(LifeOSType.label.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    // The affordance: this whole card is the point button.
                    Image(systemName: "plus").font(LifeOSType.label.weight(.bold))
                        .foregroundStyle(Editorial.quietInk(scheme))
                        .accessibilityHidden(true)
                }
                Text("\(score.current.points(side))")
                    .font(Editorial.figure(72)).tracking(Editorial.figureTracking(72))
                    .monospacedDigit().contentTransition(.numericText())
                Text("Games \(score.gamesWon(by: side))")
                    .font(LifeOSType.caption).foregroundStyle(Editorial.quietInk(scheme))
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(Space.x2)
            .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme)))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(side == .us ? ink : Editorial.rule(scheme), lineWidth: side == .us ? 1.5 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: score.current.points(side))
        .accessibilityLabel("\(name) won the rally")
        .accessibilityValue("\(score.current.points(side)) points, \(score.gamesWon(by: side)) games\(serving ? ", serving" : "")")
    }
}
