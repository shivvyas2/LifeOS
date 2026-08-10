import SwiftUI

struct QuickLogSheet: View {
    @Bindable var model: QuickLogViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Water") {
                    Stepper("\(Int(model.waterML)) ml", value: $model.waterML, in: 50...2000, step: 50)
                    Button("Add \(Int(model.waterML)) ml") {
                        if model.addWater() { dismiss() }
                    }
                }
                Section("Weight") {
                    TextField("kg", text: $model.weightText)
                        .keyboardType(.decimalPad)
                    Button("Save weight") {
                        if model.saveWeight() { dismiss() }
                    }
                    .disabled(!model.canSaveWeight)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Quick log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    QuickLogSheet(model: QuickLogViewModel())
}
