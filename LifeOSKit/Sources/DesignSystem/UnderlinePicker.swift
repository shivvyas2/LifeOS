import SwiftUI

/// A text tab row with a clear selection and comfortable touch targets.
public struct UnderlinePicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            Picker("Section", selection: $selection) {
                ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
            }
            .pickerStyle(.menu).tint(LifeOSTokens.accent)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    VStack(spacing: 0) {
                        Text(title)
                            .font(.subheadline.weight(selection == value ? .semibold : .regular))
                            .foregroundStyle(selection == value ? LifeOSTokens.primaryText.resolve(scheme) : LifeOSTokens.secondaryText.resolve(scheme))
                            .frame(maxWidth: .infinity, minHeight: 44)
                        Rectangle().fill(selection == value ? LifeOSTokens.accent : .clear).frame(height: 2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .background(alignment: .bottom) {
            Rectangle().fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.08)).frame(height: 1)
        }
    }
}
