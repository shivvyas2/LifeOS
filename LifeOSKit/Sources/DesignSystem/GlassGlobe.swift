import SwiftUI

/// A Siri-like glass slime: clear, silver, slowly morphing. Audio `intensity`
/// makes it breathe. Hue is kept out of it — the colour is the light on glass,
/// not a pink or blue fill.
public struct GlassGlobe: View {
    public var intensity: CGFloat
    public var isActive: Bool
    @Environment(\.colorScheme) private var scheme

    public init(intensity: CGFloat = 0, isActive: Bool = false) {
        self.intensity = intensity
        self.isActive = isActive
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let speed = isActive ? 1.15 : 0.42
            let phase = t * speed
            let breathe = 1 + 0.025 * sin(t * 1.35) + intensity * 0.11

            ZStack {
                SlimeBlob(time: phase, seed: 0.4)
                    .fill(Color.white.opacity(scheme == .dark ? 0.07 : 0.22))
                    .blur(radius: 20)
                    .scaleEffect(1.16)

                SlimeBlob(time: phase, seed: 1.0)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        SlimeBlob(time: phase, seed: 1.0)
                            .fill(
                                AngularGradient(
                                    colors: [
                                        .white.opacity(scheme == .dark ? 0.55 : 0.7),
                                        .white.opacity(0.04),
                                        Color(white: scheme == .dark ? 0.75 : 0.92).opacity(0.35),
                                        .white.opacity(0.06),
                                        .white.opacity(scheme == .dark ? 0.5 : 0.65),
                                    ],
                                    center: .center,
                                    angle: .degrees(t * 24)
                                )
                            )
                            .blendMode(.overlay)
                    }
                    .overlay {
                        // Inner caustic, like light sliding across wet glass.
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 70, height: 160)
                            .rotationEffect(.degrees(18 + sin(t * 0.7) * 12))
                            .offset(x: CGFloat(sin(phase * 0.8) * 18),
                                    y: CGFloat(cos(phase * 0.6) * 10) - 20)
                            .blur(radius: 10)
                            .blendMode(.screen)
                            .mask(SlimeBlob(time: phase, seed: 1.0))
                    }
                    .overlay {
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(scheme == .dark ? 0.7 : 0.9), .clear],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 48
                                )
                            )
                            .frame(width: 92, height: 64)
                            .offset(x: -34, y: -42)
                            .blur(radius: 1.5)
                    }
                    .overlay {
                        SlimeBlob(time: phase, seed: 1.0)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(scheme == .dark ? 0.55 : 0.85),
                                        .white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.3
                            )
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.12),
                            radius: 22 + intensity * 10, y: 12)
            }
            .scaleEffect(breathe)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Organic closed curve. Eight radial points drift so the mass reads as slime
/// rather than a spinning sphere.
struct SlimeBlob: Shape {
    var time: Double
    var seed: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let count = 8
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let angle = (Double(index) / Double(count)) * .pi * 2 - .pi / 2
            let jitter = 0.11 * sin(time * 1.6 + angle * 3 + seed)
                + 0.07 * sin(time * 2.4 + angle * 5 + seed * 1.7)
            let rad = radius * (0.86 + jitter)
            points.append(CGPoint(
                x: center.x + CGFloat(cos(angle)) * rad,
                y: center.y + CGFloat(sin(angle)) * rad
            ))
        }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        var path = Path()
        path.move(to: mid(points[0], points[1]))
        for index in 0..<count {
            let current = points[index]
            let next = points[(index + 1) % count]
            path.addQuadCurve(to: mid(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }
}

/// Frosted circular chrome. The whole circle is the hit target — a chevron
/// glyph alone is a few points wide and misses most taps.
public struct GlassCircleButton: View {
    private let systemImage: String
    private let size: CGFloat
    private let emphasized: Bool
    private let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(systemImage: String, size: CGFloat = 52, emphasized: Bool = false,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.size = size
        self.emphasized = emphasized
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                if emphasized {
                    Circle().fill(LifeOSTokens.fabFill.resolve(scheme))
                }
                Circle()
                    .strokeBorder(
                        Color.white.opacity(scheme == .dark ? 0.18 : 0.55),
                        lineWidth: 1
                    )
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(emphasized
                        ? LifeOSTokens.fabGlyph.resolve(scheme)
                        : LifeOSTokens.primaryText.resolve(scheme))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 10, y: 4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

#Preview("Light") {
    ZStack {
        LifeOSTokens.canvas.resolve(.light).ignoresSafeArea()
        GlassGlobe(intensity: 0.4, isActive: true)
            .frame(width: 240)
    }
}

#Preview("Dark") {
    ZStack {
        LifeOSTokens.canvas.resolve(.dark).ignoresSafeArea()
        GlassGlobe(intensity: 0.6, isActive: true)
            .frame(width: 240)
    }
    .preferredColorScheme(.dark)
}
