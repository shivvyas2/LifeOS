import Foundation

public struct MailItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let threadId: String
    public let sender: String
    public let senderEmail: String
    public let subject: String
    public let snippet: String
    public let receivedAt: Date
    public let isUnread: Bool

    public init(id: String, threadId: String, sender: String, senderEmail: String, subject: String,
                snippet: String, receivedAt: Date, isUnread: Bool) {
        self.id = id; self.threadId = threadId; self.sender = sender; self.senderEmail = senderEmail
        self.subject = subject; self.snippet = snippet; self.receivedAt = receivedAt; self.isUnread = isUnread
    }
}

/// The two Gmail calls the inbox makes, and reading their answers. Only
/// metadata and Gmail's own snippet: bodies are never fetched.
public enum GmailAPI {
    public static let query = "in:inbox category:primary is:important newer_than:2d"
    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me/messages"

    public static func listURL() -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "25")]
        return components.url!
    }

    public static func messageURL(id: String) -> URL {
        var components = URLComponents(string: "\(base)/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        return components.url!
    }

    public static func messageIDs(from data: Data) -> [String] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return ((json?["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
    }

    public static func item(from data: Data) -> MailItem? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = json["id"] as? String else { return nil }
        let headers = ((json["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
        func header(_ name: String) -> String? {
            headers.first { ($0["name"] as? String)?.lowercased() == name.lowercased() }?["value"] as? String
        }
        let from = sender(from: header("From") ?? "")
        let millis = Double(json["internalDate"] as? String ?? "") ?? 0
        let labels = json["labelIds"] as? [String] ?? []
        return MailItem(id: id, threadId: json["threadId"] as? String ?? id, sender: from.name, senderEmail: from.email,
                        subject: decodeWords(header("Subject") ?? "(no subject)"),
                        snippet: json["snippet"] as? String ?? "",
                        receivedAt: Date(timeIntervalSince1970: millis / 1_000), isUnread: labels.contains("UNREAD"))
    }

    /// `"Priya Shah" <p@x.com>` → (Priya Shah, p@x.com); a bare address is
    /// its own name; MIME encoded-words are decoded.
    public static func sender(from value: String) -> (name: String, email: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close else {
            return (trimmed, trimmed)
        }
        let email = String(trimmed[trimmed.index(after: open)..<close])
        var name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
        name = decodeWords(name)
        return (name.isEmpty ? email : name, email)
    }

    /// RFC 2047 encoded-words (`=?UTF-8?B?…?=`, `=?UTF-8?Q?…?=`).
    static func decodeWords(_ text: String) -> String {
        guard text.contains("=?") else { return text }
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let kindRange = Range(match.range(at: 2), in: text),
                  let bodyRange = Range(match.range(at: 3), in: text) else { continue }
            let body = String(text[bodyRange])
            var decoded: String?
            if text[kindRange].uppercased() == "B" {
                decoded = Data(base64Encoded: body).flatMap { String(data: $0, encoding: .utf8) }
            } else {
                var bytes: [UInt8] = []
                var index = body.startIndex
                while index < body.endIndex {
                    let character = body[index]
                    if character == "=", let end = body.index(index, offsetBy: 3, limitedBy: body.endIndex),
                       let byte = UInt8(body[body.index(after: index)..<end], radix: 16) {
                        bytes.append(byte); index = end
                    } else {
                        bytes.append(contentsOf: Array((character == "_" ? " " : String(character)).utf8))
                        index = body.index(after: index)
                    }
                }
                decoded = String(bytes: bytes, encoding: .utf8)
            }
            if let decoded { result.replaceSubrange(Range(match.range, in: result) ?? whole, with: decoded) }
        }
        return result
    }
}
