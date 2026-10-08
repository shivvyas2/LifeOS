import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
import Persistence

/// Brings a month of a card's charges in from its statement.
///
/// Pick the card, pick the file, check what was found, import. Nothing is
/// saved until the last step: a PDF is read by a model that can misread, and
/// purchases already quick-added come back on the statement, so the review
/// shows both and leaves the likely duplicates unticked.
struct StatementImportSheet: View {
    let cards: [MoneyCardSummary]
    var initialCard: String?
    let duplicates: ([StatementLine], String) -> Set<UUID>
    let onImport: ([StatementLine], String) -> Void
    var onAddCard: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var cardKey: String?
    @State private var choosingFile = false
    @State private var reading = false
    @State private var failure: String?
    @State private var lines: [StatementLine] = []
    @State private var flagged: Set<UUID> = []
    @State private var included: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                if cards.isEmpty {
                    Section {
                        Text("Add the card first, so its charges have somewhere to go.")
                        Button("Add a card", systemImage: "plus") {
                            dismiss()
                            onAddCard()
                        }
                    }
                } else {
                    Section {
                        CardPickerRow(cards: cards, selection: $cardKey)
                        Button(lines.isEmpty ? "Choose a statement" : "Choose a different file",
                               systemImage: "doc.badge.plus") { choosingFile = true }
                            .disabled(cardKey == nil || reading)
                    } footer: {
                        Text("A PDF or CSV from your bank's website. It's read on this iPhone and never uploaded.")
                    }
                }

                if reading {
                    Section {
                        HStack(spacing: Space.x1) {
                            ProgressView()
                            Text("Reading the statement…")
                        }
                    }
                }

                if let failure {
                    Section { Text(failure).foregroundStyle(.red) }
                }

                if !lines.isEmpty { review }
            }
            .navigationTitle("Import a statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(included.count)") {
                        guard let cardKey else { return }
                        onImport(lines.filter { included.contains($0.id) }, cardKey)
                        dismiss()
                    }
                    .disabled(included.isEmpty || cardKey == nil)
                }
            }
            .fileImporter(isPresented: $choosingFile,
                          allowedContentTypes: [.pdf, .commaSeparatedText, .plainText]) { result in
                if case .success(let url) = result { read(url) }
            }
            .onAppear { cardKey = initialCard ?? cards.first?.id }
            .onChange(of: cardKey) { reflag() }
        }
    }

    @ViewBuilder
    private var review: some View {
        Section {
            ForEach(lines) { line in
                Button { toggle(line.id) } label: {
                    HStack(spacing: Space.x1) {
                        Image(systemName: included.contains(line.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(included.contains(line.id)
                                             ? MoneyPalette.ink.resolve(scheme) : MoneyPalette.quietInk(scheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.merchant)
                                .font(LifeOSType.label.weight(.semibold))
                                .foregroundStyle(MoneyPalette.ink.resolve(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(flagged.contains(line.id)
                                 ? "\(line.date.formatted(.dateTime.month(.abbreviated).day())) · Looks like one you already have"
                                 : line.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(LifeOSType.caption)
                                .foregroundStyle(MoneyPalette.quietInk(scheme))
                                .lineLimit(1)
                        }
                        Spacer(minLength: Space.x1)
                        MoneyFigure(amount: line.amount, size: 15, showsSign: true).fixedSize()
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Found \(lines.count)")
        } footer: {
            if !flagged.isEmpty {
                Text("\(flagged.count) match a charge already in the app by amount and date, so they're unticked. Tick any that are really new.")
            }
        }
    }

    private func toggle(_ id: UUID) {
        if included.contains(id) { included.remove(id) } else { included.insert(id) }
    }

    private func read(_ url: URL) {
        failure = nil
        reading = true
        lines = []
        Task {
            do {
                let found = try await StatementReader.read(url)
                lines = found
                reflag()
            } catch {
                failure = error.localizedDescription
            }
            reading = false
        }
    }

    private func reflag() {
        guard let cardKey, !lines.isEmpty else { return }
        flagged = duplicates(lines, cardKey)
        included = Set(lines.map(\.id)).subtracting(flagged)
    }
}
