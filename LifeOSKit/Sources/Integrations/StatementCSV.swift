import Foundation
import Persistence

/// Reads a card statement exported as CSV into `StatementLine`s.
///
/// Banks agree on almost nothing. Chase signs purchases negative; Discover,
/// Apple Card and Amex sign them positive; Capital One splits them into Debit
/// and Credit columns. So the columns are found by name, and the sign is
/// decided per file: an explicit Debit/Credit split wins, then a Type column,
/// and otherwise whichever sign most rows carry is taken to be a purchase,
/// because a card statement is mostly purchases.
///
/// Payments to the card are dropped. They are money moving between your own
/// accounts, and the checking side of the same payment is already in the
/// app; keeping both would count it as income on the card.
public enum StatementCSV {
    public enum Failure: Error, Equatable {
        /// No header row with a date, a description and an amount was found.
        case unrecognisedColumns
    }

    public static func parse(_ text: String) throws -> [StatementLine] {
        let rows = records(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let headerIndex = rows.firstIndex(where: { Columns($0) != nil }),
              let columns = Columns(rows[headerIndex])
        else { throw Failure.unrecognisedColumns }

        struct Raw { let date: Date; let value: Double; let merchant: String; let isCredit: Bool?; var isPayment = false }
        var raws: [Raw] = []
        for row in rows[(headerIndex + 1)...] {
            guard let date = row[safe: columns.date].flatMap(Self.date),
                  let merchant = row[safe: columns.description]?.trimmingCharacters(in: .whitespaces),
                  !merchant.isEmpty
            else { continue }

            if let debit = columns.debit, let credit = columns.credit {
                if let spent = row[safe: debit].flatMap(Self.number), spent != 0 {
                    raws.append(Raw(date: date, value: abs(spent), merchant: merchant, isCredit: false))
                } else if let back = row[safe: credit].flatMap(Self.number), back != 0 {
                    raws.append(Raw(date: date, value: abs(back), merchant: merchant, isCredit: true))
                }
                continue
            }

            guard let amountColumn = columns.amount,
                  let value = row[safe: amountColumn].flatMap(Self.number), value != 0
            else { continue }
            let type = columns.type.flatMap { row[safe: $0] }
            raws.append(Raw(date: date, value: value, merchant: merchant,
                            isCredit: type.flatMap(Self.typeIsCredit),
                            isPayment: type?.lowercased().contains("payment") ?? false))
        }

        // Which sign is a purchase in this file, for rows with no Type to say.
        let positives = raws.filter { $0.isCredit == nil && $0.value > 0 }.count
        let negatives = raws.filter { $0.isCredit == nil && $0.value < 0 }.count
        let purchasesArePositive = positives >= negatives

        return raws.compactMap { raw in
            let spent: Bool
            if let isCredit = raw.isCredit {
                spent = !isCredit
            } else {
                spent = purchasesArePositive ? raw.value > 0 : raw.value < 0
            }
            if raw.isPayment || (!spent && isCardPayment(raw.merchant)) { return nil }
            let amount = abs(raw.value)
            return StatementLine(date: raw.date, amount: spent ? -amount : amount, merchant: raw.merchant)
        }
    }

    /// "Payment Thank You", "AUTOPAY PAYMENT", "Online payment, thank you".
    public static func isCardPayment(_ description: String) -> Bool {
        let text = description.lowercased()
        return text.contains("payment") || text.contains("autopay") || text.contains("thank you")
    }

    static func typeIsCredit(_ type: String) -> Bool? {
        let text = type.lowercased()
        if text.contains("payment") || text.contains("credit") || text.contains("return")
            || text.contains("refund") { return true }
        if text.contains("sale") || text.contains("purchase") || text.contains("debit")
            || text.contains("fee") || text.contains("interest") { return false }
        return nil
    }

    // MARK: - Columns

    struct Columns {
        let date: Int
        let description: Int
        let amount: Int?
        let debit: Int?
        let credit: Int?
        let type: Int?

        init?(_ header: [String]) {
            let names = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            func first(_ test: (String) -> Bool) -> Int? { names.firstIndex(where: test) }

            // The transaction date, not the posting date, where both exist.
            guard let date = first({ $0.contains("trans") && $0.contains("date") })
                    ?? first({ $0 == "date" || $0.hasPrefix("date") })
                    ?? first({ $0.contains("date") && !$0.contains("post") && !$0.contains("clear") }),
                  let description = first({ $0.contains("description") })
                    ?? first({ $0 == "merchant" || $0 == "payee" || $0 == "name" })
            else { return nil }

            let amount = first { $0.hasPrefix("amount") }
            let debit = first { $0 == "debit" || $0.hasPrefix("debit ") }
            let credit = first { $0 == "credit" || $0.hasPrefix("credit ") }
            guard amount != nil || (debit != nil && credit != nil) else { return nil }

            self.date = date
            self.description = description
            self.amount = amount
            self.debit = debit
            self.credit = credit
            self.type = first { $0 == "type" || $0 == "transaction type" }
        }
    }

    // MARK: - Fields

    private static let dateFormats = ["MM/dd/yyyy", "M/d/yyyy", "yyyy-MM-dd", "MM/dd/yy", "M/d/yy", "MMM d, yyyy", "dd MMM yyyy"]

    public static func date(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    /// "$1,234.56", "-12.30", "(45.00)" for a negative, "12.30 CR".
    static func number(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        var negative = false
        if value.hasPrefix("(") && value.hasSuffix(")") {
            negative = true
            value = String(value.dropFirst().dropLast())
        }
        if value.uppercased().hasSuffix("CR") {
            negative = true
            value = String(value.dropLast(2))
        }
        value = value.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let number = Double(value) else { return nil }
        return negative ? -abs(number) : number
    }

    /// RFC 4180 records: quoted fields may hold commas, newlines and doubled
    /// quotes.
    static func records(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var iterator = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = nil

        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": quoted = true
            case ",": record.append(field); field = ""
            case "\n", "\r": record.append(field); records.append(record); record = []; field = ""
            default: field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
