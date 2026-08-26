import SwiftUI
import DesignSystem

/// Free-text entry. A journal has no title and no fields to fill in. Asking
/// for either is friction on the one thing that has to stay effortless.
struct JournalEntrySheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(LifeOSType.body)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("How did today feel?")
                            .font(LifeOSType.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 21)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { focused = true }
        }
    }
}

#Preview {
    JournalEntrySheet { _ in }
}
