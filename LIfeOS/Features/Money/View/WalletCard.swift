import SwiftUI
import DesignSystem
import Persistence

/// A card at wallet size: the face's colour as a panel along the top with
/// the balance on it, a black body below with the card's name and this
/// month's charges, and the colour again as an edge under the card, as if
/// it sat on a stack.
///
/// The colours are the catalog face's, so a Chase reads blue, a Discover
/// gold, a Zolve orange-red and the Chase debit as a red blade on black. The
/// body stays black in both appearances so every card sits in the same
/// editorial frame and only the colour tells them apart.
struct WalletCard: View {
    let card: MoneyCardSummary
    var width: CGFloat = 300

    private var height: CGFloat { width / 1.36 }
    private var lip: CGFloat { width * 0.03 }
    private var radius: CGFloat { width * 0.085 }
    private var inset: CGFloat { width * 0.026 }
    private var style: CardFaceStyle { card.style }
    private var base: Color { Color(hex: style.base) }
    private var accent: Color { Color(hex: style.accent) }
    private var panelInk: Color { style.darkInk ? Color.black.opacity(0.82) : Color.white.opacity(0.96) }
    private static let bodyColour = Color(red: 0.035, green: 0.035, blue: 0.04)

    /// The whole card's height, edge included, for anything laid beside it.
    static func totalHeight(width: CGFloat) -> CGFloat { width / 1.36 + width * 0.06 }
    private var totalHeight: CGFloat { Self.totalHeight(width: width) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Self.bodyColour)
                .frame(height: height + lip * 2)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(edge)
                .frame(height: height + lip)
            face
        }
        .frame(width: width, height: totalHeight, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityName)
        .accessibilityValue(accessibilityValue)
    }

    private var face: some View {
        let panelWidth = width - inset * 2
        let panelHeight = height * 0.6
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Self.bodyColour)

            panelFill
                .frame(width: panelWidth, height: panelHeight)
                .clipShape(WalletPanelShape(radius: radius - inset))
                .overlay(WalletPanelShape(radius: radius - inset)
                    .stroke(accent.opacity(style.pattern == .saber ? 0.45 : 0), lineWidth: 1))
                .overlay(alignment: .topLeading) { panelContent.frame(width: panelWidth, height: panelHeight) }
                .padding(inset)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: width * 0.07, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: width * 0.05, weight: .regular).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: panelWidth * 0.5, alignment: .leading)
            .padding(.leading, inset + width * 0.055)
            .padding(.top, inset + panelHeight * WalletPanelShape.shoulder + width * 0.035)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    amount(card.monthSpend, size: width * 0.058, ink: .white)
                    Text(card.monthCount == 1 ? "1 charge this month" : "\(card.monthCount) charges this month")
                        .font(.system(size: width * 0.037, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(card.network.displayName)
                    .font(.system(size: width * (card.network == .mastercard ? 0.045 : 0.055),
                                  weight: .heavy).italic())
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, width * 0.06)
            .padding(.bottom, width * 0.05)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The issuer top left; the balance top right, the way a banking app
    /// leads with it. A hand-added card has no balance, so it leads with the
    /// month instead.
    private var panelContent: some View {
        HStack(alignment: .top) {
            Text(card.issuer.isEmpty ? card.kind.uppercased() : card.issuer.uppercased())
                .font(.system(size: width * 0.042, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(panelInk.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                amount(card.balance ?? card.monthSpend, size: width * 0.115, ink: panelInk, weight: .light)
                Text(card.balance == nil ? "THIS MONTH" : (card.kind == "Debit" ? "AVAILABLE" : "BALANCE"))
                    .font(.system(size: width * 0.036, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(panelInk.opacity(0.8))
            }
        }
        .padding(width * 0.045)
    }

    private var subtitle: String {
        [card.kind, card.mask.map { "•• \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// Exact to the cent, the cents a step quieter, as everywhere on Money.
    private func amount(_ value: Double, size: CGFloat, ink: Color, weight: Font.Weight = .semibold) -> some View {
        let parts = MoneyParts(value)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(parts.isNegative ? "-" : "")$\(parts.wholeText)")
            Text(".\(parts.centsText)").foregroundStyle(ink.opacity(0.6))
        }
        .font(.system(size: size, weight: weight).monospacedDigit())
        .foregroundStyle(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var panelFill: some View {
        if style.pattern == .saber {
            // The blade runs under the name's shoulder, clear of the balance.
            SaberField(base: base, blade: accent, length: width * 1.6, thickness: max(3, width * 0.012),
                       drop: height * 0.21, angle: -9)
        } else {
            ZStack {
                LinearGradient(colors: [accent, base], startPoint: .topLeading, endPoint: .bottomTrailing)
                // A soft diagonal sheen, so the colour reads as a material
                // rather than a flat swatch.
                LinearGradient(colors: [.white.opacity(0), .white.opacity(style.darkInk ? 0.28 : 0.2), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.35)
                    .rotationEffect(.degrees(28))
                    .offset(x: -width * 0.18)
                    .blur(radius: width * 0.03)
            }
        }
    }

    private var edge: LinearGradient {
        style.pattern == .saber
            ? LinearGradient(colors: [accent.opacity(0.6), accent, accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [base, accent, base], startPoint: .leading, endPoint: .trailing)
    }

    private var accessibilityValue: String {
        let spend = MoneyScreen.money(card.monthSpend) ?? ""
        guard let balance = card.balance, let figure = MoneyScreen.money(balance) else {
            return "\(spend) this month"
        }
        return "\(card.kind == "Debit" ? "Available" : "Balance") \(figure), \(spend) this month"
    }
}

/// The coloured panel: full width along the top, its bottom edge stepping
/// down in one smooth curve from a shoulder on the left, which leaves room
/// for the card's name beneath it.
struct WalletPanelShape: Shape {
    var radius: CGFloat
    /// Where the left part ends, as a share of the panel's height.
    static let shoulder: CGFloat = 0.66

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height * 0.3)
        let shoulderY = rect.height * Self.shoulder
        let curveStart = rect.width * 0.62
        let curveEnd = rect.width * 0.42
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: 0), tangent2End: CGPoint(x: rect.maxX, y: r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: curveStart, y: rect.maxY))
        path.addCurve(to: CGPoint(x: curveEnd, y: shoulderY),
                      control1: CGPoint(x: (curveStart + curveEnd) / 2, y: rect.maxY),
                      control2: CGPoint(x: (curveStart + curveEnd) / 2, y: shoulderY))
        path.addLine(to: CGPoint(x: r, y: shoulderY))
        path.addArc(tangent1End: CGPoint(x: 0, y: shoulderY), tangent2End: CGPoint(x: 0, y: shoulderY - r), radius: r)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: .zero, tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.closeSubpath()
        return path
    }
}
