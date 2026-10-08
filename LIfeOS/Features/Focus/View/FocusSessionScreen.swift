import SwiftUI
import DesignSystem
import Soundscape

/// The full-screen session: the clock, the phase, the visual, and the few
/// controls a person needs without leaving their work.
struct FocusSessionScreen: View {
    @Bindable var model: FocusSessionModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            switch model.stage {
            case .summary(let summary):
                FocusSummaryView(summary: summary, onMarkDone: model.markTaskDone, onDone: model.dismissSummary)
            default:
                running
            }
        }
    }

    private var isSleep: Bool { model.setup.mood == .sleep }

    private var background: Color {
        isSleep ? .black : LifeOSTokens.canvas.resolve(scheme)
    }

    private var running: some View {
        VStack(spacing: Space.x3) {
            HStack {
                Text(model.setup.mood.title.uppercased()).editorialEyebrow()
                Spacer()
                if let rate = model.heartRate {
                    Label("\(rate)", systemImage: "heart.fill").font(LifeOSType.label)
                        .accessibilityLabel("Heart rate \(rate)")
                }
            }
            if let title = model.taskTitle {
                Text(title).font(LifeOSType.rowTitle).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            ZStack {
                if !isSleep { FocusVisual(parameters: model.parameters, reading: model.reading).frame(height: 300) }
                VStack(spacing: Space.x1) {
                    Text(clock).font(LifeOSType.numeral(isSleep ? 40 : 72, weight: .light)).monospacedDigit()
                        .accessibilityIdentifier("focus.timer")
                    Text(model.reading.map { model.phaseTitle($0.phase) } ?? "")
                        .font(LifeOSType.label).accessibilityIdentifier("focus.phase")
                }
            }
            .opacity(isSleep ? 0.5 : 1)
            Spacer(minLength: 0)
            if let notice = model.notice {
                Text(notice).font(LifeOSType.caption).multilineTextAlignment(.center)
            }
            footnote
            controls
        }
        .padding(Space.x3)
        .foregroundStyle(isSleep ? Color.white.opacity(0.6) : LifeOSTokens.primaryText.resolve(scheme))
    }

    private var footnote: some View {
        HStack(spacing: Space.x2) {
            Text(model.activeSource.title)
            if model.activeSource == .soundscape, let texture = model.parameters?.texture, texture != .none {
                Text(textureName(texture))
            }
        }
        .font(LifeOSType.caption)
        .foregroundStyle(Editorial.quietInk(scheme))
    }

    private func textureName(_ texture: TextureKind) -> String {
        switch texture {
        case .none: ""
        case .rain: "Rain"
        case .wind: "Wind"
        case .brown: "Brown noise"
        case .hiss: "Snow"
        }
    }

    private var isHalted: Bool { model.reading?.isPaused == true || !model.soundPlaying }

    private var controls: some View {
        HStack(spacing: Space.x2) {
            Menu {
                ForEach(Mood.allCases, id: \.self) { mood in Button(mood.title) { model.changeMood(mood) } }
            } label: { Image(systemName: "waveform").frame(width: 44, height: 44) }
                .accessibilityLabel("Change mood").accessibilityIdentifier("focus.changeMood")
            Button {
                if model.reading?.isPaused == true { model.resume() }
                else if !model.soundPlaying { model.resumeSound() }
                else { model.pause() }
            } label: {
                Image(systemName: isHalted ? "play.fill" : "pause.fill").frame(width: 64, height: 64)
            }
            .accessibilityLabel(isHalted ? "Resume" : "Pause").accessibilityIdentifier("focus.pause")
            Button { model.skip() } label: { Image(systemName: "forward.end").frame(width: 44, height: 44) }
                .accessibilityLabel("Skip phase").accessibilityIdentifier("focus.skip")
            Button("End") { model.end() }
                .buttonStyle(.editorial(.quiet, size: .compact, fullWidth: false))
                .accessibilityIdentifier("focus.end")
        }
        .font(.title2)
    }

    private var clock: String {
        guard let reading = model.reading else { return "--:--" }
        let seconds = Int((reading.remaining ?? reading.focusedSeconds).rounded(.up))
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
