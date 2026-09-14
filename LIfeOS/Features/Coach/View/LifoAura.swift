import SwiftUI

enum CoachScreenStyle: String {
    case text, voice

    var accent: Color {
        self == .text ? Color(red: 0.36, green: 0.52, blue: 1) : Color(red: 0.20, green: 0.87, blue: 0.66)
    }
    var glow: Color {
        self == .text ? Color(red: 0.43, green: 0.55, blue: 1) : Color(red: 0.49, green: 0.66, blue: 0.43)
    }
    var night: Color {
        self == .text ? Color(red: 0.025, green: 0.04, blue: 0.085) : Color(red: 0.015, green: 0.045, blue: 0.035)
    }
    var card: Color {
        self == .text ? Color(red: 0.93, green: 0.95, blue: 1) : Color(red: 0.91, green: 0.97, blue: 0.94)
    }
    var cell: Color {
        self == .text ? Color(red: 0.84, green: 0.89, blue: 0.99) : Color(red: 0.79, green: 0.90, blue: 0.84)
    }
    var cardAccent: Color {
        self == .text ? Color(red: 0.18, green: 0.32, blue: 0.70) : Color(red: 0.08, green: 0.38, blue: 0.28)
    }
}

enum LifoPalette {
    static let ink = Color.white
    static let quietInk = Color.white.opacity(0.78)
    static let gold = Color(red: 0.86, green: 0.67, blue: 0.29)
}

struct LifoAura: View {
    var style: CoachScreenStyle = .text
    var intensity: CGFloat = 0
    var isActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let level = intensity.isFinite ? min(max(intensity, 0), 1) : 0
            let swell = reduceMotion || !isActive ? 1 : 1 + level * 0.06
            ZStack {
                style.night
                LinearGradient(stops: [
                    .init(color: style.glow.opacity(0.70), location: 0),
                    .init(color: style.accent.opacity(0.27), location: 0.29),
                    .init(color: style.night, location: 0.65)
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [style.glow.opacity(0.80), .clear],
                               center: .init(x: 0.72, y: 0.12), startRadius: 0,
                               endRadius: proxy.size.height * 0.44 * swell)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: level)
        }
        .ignoresSafeArea()
    }
}
