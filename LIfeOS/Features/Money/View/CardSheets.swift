import SwiftUI
import DesignSystem
import Persistence

/// "Which card paid for this?" Opened from the chip on a transaction row.
struct CardPickerSheet: View {
    let row: MoneyRow
    let cards: [MoneyCardSummary]
    let hasRule: Bool
    let onPick: (String?, Bool) -> Void
    var onAddCard: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var always: Bool

    init(row: MoneyRow, cards: [MoneyCardSummary], hasRule: Bool,
         onPick: @escaping (String?, Bool) -> Void, onAddCard: @escaping () -> Void = {}) {
        self.row = row
        self.cards = cards
        self.hasRule = hasRule
        self.onPick = onPick
        self.onAddCard = onAddCard
        _always = State(initialValue: hasRule)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Always use this card for \(row.merchant)", isOn: $always)
                } footer: {
                    Text("Applies to every charge from \(row.merchant), past and future, unless you pick a card on one of them.")
                }

                Section("Cards") {
                    ForEach(cards) { card in
                        Button {
                            onPick(card.id, always)
                            dismiss()
                        } label: {
                            HStack(spacing: Space.x2) {
                                CardFace(card: card, width: 64)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.title)
                                        .font(LifeOSType.body.weight(.semibold))
                                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                        .lineLimit(1)
                                    Text([card.mask.map { "•••• \($0)" }, card.title == card.accountName ? nil : card.accountName]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(LifeOSType.caption)
                                        .foregroundStyle(MoneyPalette.quietInk(scheme))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if card.id == row.card?.id {
                                    Image(systemName: "checkmark")
                                        .font(LifeOSType.label.weight(.bold))
                                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Add a card", systemImage: "plus") {
                        dismiss()
                        onAddCard()
                    }
                }

                Section {
                    Button("No card", role: .destructive) {
                        onPick(nil, false)
                        dismiss()
                    }
                } footer: {
                    Text("Clears your choice. If your bank said which account paid, that comes back.")
                }
            }
            .navigationTitle("Which card?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Add a card Plaid cannot see, or change how any card is drawn.
///
/// A known card is chosen from a grid of faces, which is also how the app
/// will later know its rewards. Anything else gets a plain face in a colour.
/// A Plaid card's name and last four come from the bank and are not edited
/// here; the next sync would put them back.
struct CardEditorSheet: View {
    let existing: MoneyCardSummary?
    let onSave: (CardDraft) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name: String
    @State private var mask: String
    @State private var productID: String?
    @State private var colorHex: String

    init(existing: MoneyCardSummary?, onSave: @escaping (CardDraft) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: existing?.accountName ?? "")
        _mask = State(initialValue: existing?.mask ?? "")
        _productID = State(initialValue: existing?.productID)
        _colorHex = State(initialValue: existing.map { $0.style.base } ?? CardCatalog.swatches[0])
    }

    private var isManual: Bool { existing?.isManual ?? true }

    private var trimmedName: String {
        let typed = name.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        return CardCatalog.product(id: productID)?.name ?? ""
    }

    private var canSave: Bool { !isManual || !trimmedName.isEmpty }

    private var preview: MoneyCardSummary {
        let account = MoneyAccount(
            name: isManual ? (trimmedName.isEmpty ? "Your card" : trimmedName) : (existing?.accountName ?? ""),
            type: "credit", mask: isManual ? String(mask.filter(\.isNumber).suffix(4)) : existing?.mask,
            currentBalance: 0, externalID: isManual ? nil : existing?.id,
            cardProductID: productID, faceColorHex: productID == nil ? colorHex : nil, isManual: isManual
        )
        if account.mask?.isEmpty == true { account.mask = nil }
        return MoneyCardSummary(account)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardFace(card: preview, width: 240)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.x1)
                        .listRowBackground(Color.clear)
                }

                if isManual {
                    Section {
                        TextField("Name, e.g. Zolve", text: $name)
                        TextField("Last four digits (optional)", text: $mask)
                            .keyboardType(.numberPad)
                    } footer: {
                        Text("Only the last four are kept, to tell two cards apart.")
                    }
                } else {
                    Section {
                        LabeledContent("From your bank", value: existing?.accountName ?? "")
                    }
                }

                Section("Which card is it?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.x1)], spacing: Space.x2) {
                        ForEach(CardCatalog.all) { product in
                            Button { productID = product.id } label: {
                                VStack(spacing: 4) {
                                    CardFace(card: Self.sample(product), width: 96)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 96 * 0.07, style: .continuous)
                                                .strokeBorder(MoneyPalette.ink.resolve(scheme),
                                                              lineWidth: productID == product.id ? 2.5 : 0)
                                        )
                                    Text(product.name)
                                        .font(LifeOSType.caption)
                                        .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(productID == product.id ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Space.half)
                }

                Section("Or a plain card in a colour") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: Space.x1)], spacing: Space.x1) {
                        ForEach(CardCatalog.swatches, id: \.self) { hex in
                            Button {
                                productID = nil
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                                    .overlay(Circle().strokeBorder(MoneyPalette.ink.resolve(scheme),
                                                                   lineWidth: productID == nil && colorHex == hex ? 2.5 : 0)
                                        .padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour \(hex)")
                        }
                    }
                    .padding(.vertical, Space.half)
                }

                if let onDelete, isManual, existing != nil {
                    Section {
                        Button("Delete card", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    } footer: {
                        Text("Charges you put on it keep their amounts and lose the card.")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add a card" : "Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(CardDraft(existingKey: existing?.id, name: trimmedName, productID: productID,
                                         mask: mask, colorHex: productID == nil ? colorHex : nil))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    /// A catalog card drawn on its own, for the grid.
    static func sample(_ product: CardProduct) -> MoneyCardSummary {
        MoneyCardSummary(MoneyAccount(name: product.name, type: "credit", currentBalance: 0,
                                      externalID: "sample:\(product.id)", cardProductID: product.id))
    }
}

/// The card row on the quick-add sheet.
struct CardPickerRow: View {
    let cards: [MoneyCardSummary]
    @Binding var selection: String?

    var body: some View {
        Picker("Card", selection: $selection) {
            Text("None").tag(String?.none)
            ForEach(cards) { card in
                Text([card.title, card.mask.map { "•••• \($0)" }].compactMap { $0 }.joined(separator: " "))
                    .tag(String?.some(card.id))
            }
        }
    }
}

/// What the card editor opens on: a card to restyle, or nil for a new one.
struct CardEditorTarget: Identifiable {
    let id = UUID()
    let card: MoneyCardSummary?
}
