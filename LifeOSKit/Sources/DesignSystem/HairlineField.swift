import SwiftUI

/// A field on a hairline: a leading glyph, the text, a clear glyph while
/// there is text, room for one accessory (the calendar's ask arrow), and a
/// rule underneath. Notes searches with it; the calendar finds and asks.
public struct HairlineField<Accessory: View>: View {
    @Binding var text: String
    let placeholder: String
    let glyph: String
    let submitLabel: SubmitLabel
    let focus: FocusState<Bool>.Binding?
    let onSubmit: () -> Void
    let accessory: Accessory
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, placeholder: String, glyph: String = "magnifyingglass",
                submitLabel: SubmitLabel = .search, focus: FocusState<Bool>.Binding? = nil,
                onSubmit: @escaping () -> Void = {}, @ViewBuilder accessory: () -> Accessory) {
        _text = text; self.placeholder = placeholder; self.glyph = glyph
        self.submitLabel = submitLabel; self.focus = focus; self.onSubmit = onSubmit
        self.accessory = accessory()
    }

    public var body: some View {
        let quiet = Editorial.quietInk(scheme)
        VStack(spacing: Space.half) {
            HStack(spacing: Space.x1) {
                Image(systemName: glyph).foregroundStyle(quiet)
                field
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .font(LifeOSType.body)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .onSubmit(onSubmit)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(quiet)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
                accessory
            }
            .frame(minHeight: 44)
            Hairline()
        }
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField(placeholder, text: $text).focused(focus).submitLabel(submitLabel)
        } else {
            TextField(placeholder, text: $text).submitLabel(submitLabel)
        }
    }
}

extension HairlineField where Accessory == EmptyView {
    public init(text: Binding<String>, placeholder: String, glyph: String = "magnifyingglass",
                submitLabel: SubmitLabel = .search, focus: FocusState<Bool>.Binding? = nil,
                onSubmit: @escaping () -> Void = {}) {
        self.init(text: text, placeholder: placeholder, glyph: glyph, submitLabel: submitLabel,
                  focus: focus, onSubmit: onSubmit) { EmptyView() }
    }
}
