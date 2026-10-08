import SwiftUI

/// Add sheet for a plan entry. `target` is offered only where a numeric goal
/// makes sense, so a habit never grows a meaningless milestone count.
struct AddPlanEntrySheet: View {
    let prompt: String
    let allowsTarget: Bool
    /// Content is scheduled, so it gets a date; nothing else does.
    let allowsDueDate: Bool
    let onSave: (String, String?, Double?, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var target = ""
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Detail (optional)", text: $detail)
                }
                if allowsTarget {
                    Section("Target") {
                        TextField("e.g. 4 milestones, or 10000", text: $target)
                            .keyboardType(.decimalPad)
                    }
                }
                if allowsDueDate {
                    Section("Scheduled for") {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(prompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, detail.isEmpty ? nil : detail, Double(target),
                               allowsDueDate ? dueDate : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Manual money entry. Direction is an explicit choice rather than a signed
/// number, so nobody has to remember which way the sign points.
struct AddMoneySheet: View {
    /// What a charge can go on, and the one to start on.
    var cards: [MoneyCardSummary] = []
    var initialCard: String? = nil
    let onSave: (String, Double, Bool, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var merchant = ""
    @State private var amount = ""
    @State private var category = ""
    @State private var isIncome = false
    @State private var cardKey: String?

    private var parsedAmount: Double? {
        guard let value = Double(amount), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Direction", selection: $isIncome) {
                    Text("Expense").tag(false)
                    Text("Income").tag(true)
                }
                .pickerStyle(.segmented)

                Section {
                    TextField(isIncome ? "Source" : "Merchant", text: $merchant)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    TextField("Category (optional)", text: $category)
                }

                if !cards.isEmpty && !isIncome {
                    Section {
                        CardPickerRow(cards: cards, selection: $cardKey)
                    } footer: {
                        Text("Starts on the card you used last.")
                    }
                }
            }
            .onAppear { cardKey = initialCard }
            .navigationTitle("Add transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let parsedAmount {
                            onSave(merchant, parsedAmount, isIncome, category.isEmpty ? nil : category,
                                   isIncome ? nil : cardKey)
                        }
                        dismiss()
                    }
                    .disabled(parsedAmount == nil || merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
