import SwiftUI

/// The editorial layer of the design system: paper, ink, hairline rules,
/// numbered sections and figures set large and light.
///
/// It adds no colours of its own. Paper is `LifeOSTokens.canvas`, ink is
/// `primaryText`, and the one accent is `LifeOSTokens.accent`, so a screen
/// built from these pieces sits beside every other screen without a seam.
/// What it adds is the grammar: structure drawn with rules and numbers rather
/// than with cards, shadows and tinted blocks, which is what made each module
/// look like its own app.
public enum Editorial {
    /// The ruled line between rows and under headings. Ink at low opacity
    /// rather than a grey, so it holds the same weight on paper and on black.
    public static func rule(_ scheme: ColorScheme) -> Color {
        LifeOSTokens.primaryText.resolve(scheme).opacity(scheme == .dark ? 0.18 : 0.14)
    }

    /// Ink for supporting text: present, never competing with the figure.
    public static func quietInk(_ scheme: ColorScheme) -> Color {
        LifeOSTokens.primaryText.resolve(scheme).opacity(scheme == .dark ? 0.62 : 0.55)
    }

    /// A figure set large. Light weight with tight tracking: at this size the
    /// regular weight turns a number into a slab, and the references this
    /// layer is drawn from set every headline figure thin.
    public static func figure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .default)
    }

    /// Tracking that goes with `figure`, proportional so a caller cannot pair
    /// a 96pt figure with tracking meant for 40.
    public static func figureTracking(_ size: CGFloat) -> CGFloat { -size * 0.045 }

    /// The headline face for a screen or a section: medium, tight, large.
    public static func headline(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Two-digit section numbers, so "01" and "12" line up in a column.
    public static func index(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

// MARK: - Pieces

/// A full-width hairline.
public struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        Rectangle().fill(Editorial.rule(scheme)).frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The small tracked uppercase line that sits above a heading or a figure.
    public func editorialEyebrow() -> some View {
        modifier(EditorialEyebrow())
    }
}

private struct EditorialEyebrow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.font(LifeOSType.eyebrow).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(Editorial.quietInk(scheme))
    }
}

/// A screen's masthead: eyebrow, a large headline, and an optional line of
/// support, ruled off underneath.
public struct EditorialMasthead: View {
    let eyebrow: String
    let title: String
    let detail: String?
    @Environment(\.colorScheme) private var scheme

    public init(eyebrow: String, title: String, detail: String? = nil) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(eyebrow).editorialEyebrow()
            Text(title)
                .font(Editorial.headline(34)).tracking(-1)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(LifeOSType.secondary)
                    .foregroundStyle(Editorial.quietInk(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A numbered section heading: "01" in the margin, the title beside it, a
/// rule underneath, and room for one trailing action.
///
/// The number is not decoration. It tells a person how far down a long screen
/// they are and gives every section a name they can refer back to.
public struct EditorialSectionHeader<Trailing: View>: View {
    let index: Int?
    let title: String
    let trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    public init(index: Int? = nil, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.index = index; self.title = title; self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: Space.x1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                if let index {
                    Text(Editorial.index(index))
                        .font(LifeOSType.label.monospacedDigit())
                        .foregroundStyle(Editorial.quietInk(scheme))
                        .accessibilityHidden(true)
                }
                Text(title).font(LifeOSType.sectionTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.x1)
                trailing
            }
            Hairline()
        }
    }
}

extension EditorialSectionHeader where Trailing == EmptyView {
    public init(index: Int? = nil, title: String) {
        self.init(index: index, title: title) { EmptyView() }
    }
}

/// A figure with its unit and a label, set the way the references set them:
/// the number large and light, the unit small beside it, the label above.
public struct EditorialFigure: View {
    let label: String
    let value: String
    let unit: String?
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(label: String, value: String, unit: String? = nil, size: CGFloat = 64) {
        self.label = label; self.value = value; self.unit = unit; self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(label).editorialEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: Space.half) {
                Text(value)
                    .font(Editorial.figure(size)).tracking(Editorial.figureTracking(size))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                if let unit {
                    Text(unit).font(LifeOSType.secondary)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        }
        .accessibilityElement(children: .combine)
    }
}

/// One line of a two-column table: a label on the left, its value on the
/// right, a rule underneath. The references use this in place of a card for
/// anything that is a list of facts.
public struct EditorialRow<Value: View>: View {
    let label: String
    let value: Value
    @Environment(\.colorScheme) private var scheme

    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label; self.value = value()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(label).font(LifeOSType.secondary)
                    .foregroundStyle(Editorial.quietInk(scheme))
                Spacer(minLength: Space.x1)
                value.font(LifeOSType.secondary.weight(.medium))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            Hairline()
        }
        .accessibilityElement(children: .combine)
    }
}

extension EditorialRow where Value == Text {
    public init(_ label: String, value: String) {
        self.init(label) { Text(value) }
    }
}

/// The numbered pill the references anchor a screen with ("03."). Paper on
/// ink, so it reads on both schemes and on top of any figure.
public struct IndexPill: View {
    let value: Int
    @Environment(\.colorScheme) private var scheme
    public init(_ value: Int) { self.value = value }
    public var body: some View {
        Text("\(Editorial.index(value)).")
            .font(LifeOSType.rowTitle.monospacedDigit())
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(LifeOSTokens.cardSurface.resolve(scheme)))
            .overlay(Capsule().stroke(Editorial.rule(scheme)))
    }
}

/// A small outlined capsule for a tag or a state ("Work", "On track").
/// `filled` is reserved for the one thing on screen that is live or urgent,
/// and fills with the accent.
public struct EditorialTag: View {
    let text: String
    let filled: Bool
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String, filled: Bool = false) { self.text = text; self.filled = filled }
    public var body: some View {
        Text(text).font(LifeOSType.caption.weight(.medium))
            .foregroundStyle(filled ? .white : LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background { if filled { Capsule().fill(LifeOSTokens.accent) } }
            .overlay { if !filled { Capsule().stroke(LifeOSTokens.primaryText.resolve(scheme).opacity(0.5)) } }
    }
}

/// A row of numbered text tabs that scrolls sideways when it does not fit.
///
/// `UnderlinePicker` divides the width evenly, which is right for two to four
/// short options. Past that, titles truncate or shrink to nothing; this one
/// keeps every title whole and scrolls the selected tab into view, so six
/// sections stay readable on a phone.
public struct IndexedTabStrip<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        _selection = selection; self.options = options
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            // At the largest sizes a sideways strip shows one tab at a time;
            // a menu shows them all.
            Picker("Section", selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Text("\(Editorial.index(index + 1)) \(option.1)").tag(option.0)
                }
            }
            .pickerStyle(.menu).tint(LifeOSTokens.primaryText.resolve(scheme))
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        } else {
            strip
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Space.x3) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        tab(index: index, value: option.0, title: option.1).id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background(alignment: .bottom) { Hairline() }
            // A tick under the finger, so a switch registers even when the
            // answer below looks much like the last one.
            .sensoryFeedback(.selection, trigger: selection)
            .onChange(of: selection) { _, value in
                guard let index = options.firstIndex(where: { $0.0 == value }) else { return }
                withAnimation(.snappy) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func tab(index: Int, value: Value, title: String) -> some View {
        let selected = value == selection
        return Button { selection = value } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Editorial.index(index + 1))
                        .font(LifeOSType.caption.monospacedDigit())
                        .foregroundStyle(Editorial.quietInk(scheme))
                    Text(title)
                        .font(LifeOSType.rowTitle.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? LifeOSTokens.primaryText.resolve(scheme) : Editorial.quietInk(scheme))
                }
                .frame(minHeight: 44)
                Rectangle().fill(selected ? LifeOSTokens.primaryText.resolve(scheme) : .clear).frame(height: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Fields and cards

/// The two gradient fields, drawn from the ConnectX reference: a cool grey
/// light running into warm sand and peach, and a live ember that deepens
/// from the accent to near black.
public enum EditorialFieldTone: Sendable {
    /// Readings and summaries: Health, recovery, a finished session. Ink text
    /// in light mode, paper text in dark.
    case dusk
    /// Something happening now: a workout in progress, its Lock Screen card.
    /// Dark enough throughout for white text in both schemes.
    case ember

    public func colors(_ scheme: ColorScheme) -> [Color] {
        switch (self, scheme) {
        case (.dusk, .dark):
            [Color(red: 0.13, green: 0.17, blue: 0.19), Color(red: 0.24, green: 0.18, blue: 0.15), Color(red: 0.36, green: 0.18, blue: 0.11)]
        case (.dusk, _):
            [Color(red: 0.80, green: 0.84, blue: 0.86), Color(red: 0.93, green: 0.82, blue: 0.72), Color(red: 0.96, green: 0.66, blue: 0.48)]
        case (.ember, _):
            [Color(red: 0.93, green: 0.40, blue: 0.22), Color(red: 0.62, green: 0.16, blue: 0.08), Color(red: 0.10, green: 0.04, blue: 0.03)]
        }
    }

    /// The ink that clears contrast on every stop of the field.
    public func ink(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.dusk, .dark), (.ember, _): Color(white: 0.97)
        case (.dusk, _): LifeOSTokens.primaryText.resolve(.light)
        }
    }
}

/// A screen's one hero: content on a gradient field with large corners.
///
/// One per screen, the way the reference uses a single field per page.
/// Everything else on the screen sits on paper, so the field reads as the
/// headline rather than as one tint among six.
public struct EditorialField<Content: View>: View {
    let tone: EditorialFieldTone
    let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(_ tone: EditorialFieldTone = .dusk, @ViewBuilder content: () -> Content) {
        self.tone = tone; self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) { content }
            .foregroundStyle(tone.ink(scheme))
            .padding(Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: tone.colors(scheme), startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
    }
}

extension View {
    /// A card on paper: the card surface with a hairline edge, and no tint.
    /// What every card that is not the screen's hero becomes.
    public func editorialCard(padding: CGFloat = Space.x2 + 4, radius: CGFloat = Radius.medium + 4) -> some View {
        modifier(EditorialCard(padding: padding, radius: radius))
    }
}

private struct EditorialCard: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Editorial.rule(scheme)))
    }
}
