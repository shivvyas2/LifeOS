import SwiftUI
import Persistence

/// Budgets: the bucket list, and one bucket's name, limit and claims.
/// Follows `AddMoneySheet`'s form idiom. The store owns the single-holder
/// rule; this sheet only says when saving will move a key from another
/// bucket.
struct BucketEditorSheet: View {
    let model: MoneyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditingBucket?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.buckets, id: \.id) { bucket in
                    Button {
                        editing = EditingBucket(bucket)
                    } label: {
                        HStack {
                            Text(bucket.name).foregroundStyle(.primary)
                            Spacer()
                            Text(bucket.monthlyLimit.formatted(
                                .currency(code: "USD").precision(.fractionLength(0))
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        model.deleteBucket(id: model.buckets[offset].id)
                    }
                }

                Button("New bucket") { editing = EditingBucket() }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { bucket in
                BucketForm(model: model, bucket: bucket)
            }
        }
    }
}

/// A value copy of what the form edits, so cancel abandons it untouched.
private struct EditingBucket: Identifiable {
    let id: UUID?
    var name: String
    var limit: String
    var claimed: Set<String>

    init() {
        id = nil
        name = ""
        limit = ""
        claimed = []
    }

    init(_ bucket: SpendBucket) {
        id = bucket.id
        name = bucket.name
        limit = String(Int(bucket.monthlyLimit.rounded()))
        claimed = Set(bucket.claimedRaw)
    }
}

private struct BucketForm: View {
    let model: MoneyViewModel
    @State var bucket: EditingBucket
    @Environment(\.dismiss) private var dismiss

    private var parsedLimit: Double? {
        guard let value = Double(bucket.limit), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $bucket.name)
                    TextField("Monthly limit", text: $bucket.limit)
                        .keyboardType(.decimalPad)
                }

                Section("Counts") {
                    if model.claimableCategories().isEmpty {
                        Text("Categories appear here once you have transactions.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.claimableCategories()) { category in
                        Button {
                            if bucket.claimed.contains(category.id) {
                                bucket.claimed.remove(category.id)
                            } else {
                                bucket.claimed.insert(category.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.label).foregroundStyle(.primary)
                                    if let holder = category.holder,
                                       !bucket.claimed.contains(category.id) {
                                        Text("Held by \(holder), saving moves it here")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if bucket.claimed.contains(category.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(bucket.id == nil ? "New bucket" : "Edit bucket")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let parsedLimit {
                            model.saveBucket(
                                id: bucket.id, name: bucket.name,
                                limit: parsedLimit, claimed: bucket.claimed
                            )
                        }
                        dismiss()
                    }
                    .disabled(
                        parsedLimit == nil
                        || bucket.name.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
    }
}
