import Foundation
import FoundationModels
import PDFKit
import Persistence
import Integrations

/// Turns a statement file into rows, on the phone.
///
/// A CSV is read by its columns. A PDF has no columns, and every bank lays one
/// out differently, so its text is pulled out with PDFKit and Apple's
/// on-device model reads the transactions out of it. Nothing leaves the phone
/// and nothing is billed. The model can misread an odd layout, which is why
/// the import always ends on a review screen rather than a save.
enum StatementReader {
    enum Failure: LocalizedError {
        case unreadable
        case noText
        case modelUnavailable
        case nothingFound

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file couldn't be opened."
            case .noText: "This PDF has no text in it, only images. Download the statement from your bank's website rather than scanning it."
            case .modelUnavailable: "Reading PDFs needs Apple Intelligence turned on. You can export a CSV from your bank instead."
            case .nothingFound: "No transactions were found in that file."
            }
        }
    }

    static func read(_ url: URL) async throws -> [StatementLine] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let lines: [StatementLine]
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
            lines = try await readPDF(document)
        } else {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { throw Failure.unreadable }
            lines = try StatementCSV.parse(text)
        }
        guard !lines.isEmpty else { throw Failure.nothingFound }
        return lines.sorted { $0.date > $1.date }
    }

    // MARK: - PDF

    @Generable
    struct Extracted {
        @Guide(description: "Every purchase, refund, fee or interest charge listed in the text. Skip balances, totals, headings and payments made to the card.")
        var transactions: [ExtractedRow]
    }

    @Generable
    struct ExtractedRow {
        @Guide(description: "Transaction date as yyyy-MM-dd. Use the statement's year when the text shows only month and day.")
        var date: String
        @Guide(description: "Merchant or description exactly as printed")
        var merchant: String
        @Guide(description: "Amount as a positive number, without a currency sign")
        var amount: Double
        @Guide(description: "true for a refund, return or credit to the card; false for a purchase, fee or interest")
        var isCredit: Bool
    }

    /// The on-device model has a small context window, so the text goes in
    /// page-sized pieces. Pages with no amounts on them are skipped.
    static func readPDF(_ document: PDFDocument) async throws -> [StatementLine] {
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            .filter { $0.contains(".") && $0.rangeOfCharacter(from: .decimalDigits) != nil }
        guard !pages.isEmpty else { throw Failure.noText }
        guard SystemLanguageModel.default.availability == .available else { throw Failure.modelUnavailable }

        let year = Calendar.current.component(.year, from: .now)
        var lines: [StatementLine] = []
        for chunk in chunks(pages, limit: 2_400) {
            let session = LanguageModelSession(instructions: """
                You read credit card statements. List each transaction in the text. \
                The statement is from around \(year); if a date has no year, use the year that \
                keeps it on or before today.
                """)
            do {
                let response = try await session.respond(to: chunk, generating: Extracted.self)
                lines += response.content.transactions.compactMap(line)
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                // One oversize page should not sink the whole statement.
                continue
            }
        }
        return lines
    }

    static func line(_ row: ExtractedRow) -> StatementLine? {
        let merchant = row.merchant.trimmingCharacters(in: .whitespaces)
        guard !merchant.isEmpty, row.amount > 0, row.amount.isFinite,
              let date = StatementCSV.date(row.date),
              date <= Date.now.addingTimeInterval(86_400)
        else { return nil }
        if row.isCredit && StatementCSV.isCardPayment(merchant) { return nil }
        return StatementLine(date: date, amount: row.isCredit ? row.amount : -row.amount, merchant: merchant)
    }

    /// Page text joined into pieces under `limit` characters, splitting a long
    /// page on line breaks.
    static func chunks(_ pages: [String], limit: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for line in pages.joined(separator: "\n").split(separator: "\n", omittingEmptySubsequences: true) {
            if current.count + line.count + 1 > limit, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current += line + "\n"
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
