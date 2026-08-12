import Foundation

/// Splits a page envelope into one payload per record, keyed by that record's
/// provider id, so the archive stores exactly what arrived rather than a
/// re-encoding of a decoded struct.
enum WhoopRawSplit {
    static func records(inPage data: Data) throws -> [(externalID: String, payload: Data)] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [[String: Any]] else { return [] }

        return try records.compactMap { record in
            guard let id = identifier(in: record) else { return nil }
            return (id, try JSONSerialization.data(withJSONObject: record))
        }
    }

    /// Recovery carries no `id`; it is identified by the cycle it scores.
    static func identifier(in record: [String: Any]) -> String? {
        if let id = record["id"] as? String { return id }
        if let id = record["id"] as? Int { return String(id) }
        if let id = record["cycle_id"] as? Int { return String(id) }
        if let id = record["cycle_id"] as? String { return id }
        return nil
    }
}
