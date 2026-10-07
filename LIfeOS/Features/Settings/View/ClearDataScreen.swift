import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// Clears the kinds of data the person ticks, on the server first and then on
/// this phone, so a dropped connection never leaves the phone showing as gone
/// what the server still holds.
struct ClearDataScreen: View {
    var client: any AccountDataClienting = AccountDataClient()

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<DataCategory> = []
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var result: String?

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var canClear: Bool { !selected.isEmpty && confirmation == "CLEAR" && !isWorking }

    static func whereItLives(_ category: DataCategory) -> String {
        switch category {
        case .notes: "On this phone and in your synced notes."
        case .habits: "On this phone only."
        case .health: "On this phone, and older copies on our server."
        case .money: "On this phone only. Your bank stays connected."
        case .chats: "On this phone only."
        case .messages: "On our server. Clearing a conversation clears it for the other person too: it is one message, not two copies."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "Your data", title: "Clear data",
                                  detail: "Tick what to clear. Your account, name and friends stay.")
                VStack(spacing: 0) {
                    ForEach(DataCategory.allCases, id: \.self) { category in
                        row(category)
                        if category != DataCategory.allCases.last { Hairline() }
                    }
                }
                HairlineField(text: $confirmation, placeholder: "Type CLEAR to confirm", glyph: "exclamationmark.triangle",
                              submitLabel: .done)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Clear selected…") { Task { await clear() } }
                    .buttonStyle(.editorial(.destructive, fullWidth: true))
                    .disabled(!canClear)
                if let result {
                    Text(result).font(LifeOSType.secondary).foregroundStyle(ink)
                }
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("Clear data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ category: DataCategory) -> some View {
        let isOn = selected.contains(category)
        return Button {
            if isOn { selected.remove(category) } else { selected.insert(category) }
        } label: {
            HStack(alignment: .top, spacing: Space.x2) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(LifeOSType.rowTitle).foregroundStyle(ink)
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(category.title).font(LifeOSType.rowTitle).foregroundStyle(ink)
                    Text(Self.whereItLives(category)).font(LifeOSType.caption).foregroundStyle(quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.x2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityValue(isOn ? "selected" : "not selected")
        .accessibilityHint(Self.whereItLives(category))
    }

    private func clear() async {
        isWorking = true
        defer { isWorking = false }
        if selected.contains(where: \.hasServerRows) {
            do { try await client.clear(selected) } catch {
                result = "Could not clear. Nothing was removed from this phone."
                return
            }
        }
        do {
            try LocalDataEraser(context: context, defaults: .currentAccount).erase(selected)
        } catch {
            result = "Could not clear. Nothing was removed from this phone."
            return
        }
        result = "Cleared."
        selected = []
        confirmation = ""
        try? await Task.sleep(for: .seconds(1))
        dismiss()
    }
}
