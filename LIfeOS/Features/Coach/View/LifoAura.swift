import SwiftUI
import DesignSystem

/// Warm charcoal, amber light, and cream keep the coach in the app's orange theme.
enum LifoPalette {
    static let night = Color(red: 0.105, green: 0.105, blue: 0.085)
    static let amber = Color(red: 0.58, green: 0.43, blue: 0.16)
    static let gold = Color(red: 0.86, green: 0.67, blue: 0.29)
    static let ink = Color(red: 0.98, green: 0.96, blue: 0.90)
    static let quietInk = ink.opacity(0.8)
    static let raised = Color(red: 0.22, green: 0.20, blue: 0.15)
}

struct LifoAura: View {
    var intensity: CGFloat = 0
    var isActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            let level = intensity.isFinite ? min(max(intensity, 0), 1) : 0
            let swell = reduceMotion || !isActive ? 1 : 1 + level * 0.12
            ZStack {
                LifoPalette.night
                LinearGradient(colors: [LifoPalette.amber.opacity(0.42), LifoPalette.night.opacity(0)],
                               startPoint: .topLeading, endPoint: .bottom)
                RadialGradient(colors: [LifoPalette.gold.opacity(0.17), .clear],
                               center: .init(x: 0.45, y: 0.19), startRadius: 0, endRadius: side * 0.44 * swell)
                RadialGradient(colors: [LifeOSTokens.accent.opacity(0.09), .clear],
                               center: .init(x: 0.9, y: 0.45), startRadius: 0, endRadius: side * 0.35)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: level)
        }
        .ignoresSafeArea()
    }
}

#Preview { LifoAura(intensity: 0.3, isActive: true) }
