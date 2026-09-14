import Foundation

public struct InboxEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let ownerID: String
    public let text: String
    public let trigger: String
    public let day: String
    public let receivedAt: Date
    public var isRead: Bool
    public init(ownerID: String, text: String, trigger: String, day: String,
                receivedAt: Date = .now, isRead: Bool = false) {
        self.id = "\(day)|\(trigger)"
        self.ownerID = ownerID; self.text = text; self.trigger = trigger; self.day = day
        self.receivedAt = receivedAt; self.isRead = isRead
    }
    public static func inserting(_ entry: Self, into entries: [Self], ownerID: String) -> [Self] {
        guard entry.ownerID == ownerID else { return entries.filter { $0.ownerID == ownerID } }
        var result = entries.filter { $0.ownerID == ownerID }
        if !result.contains(where: { $0.id == entry.id }) { result.append(entry) }
        return Array(result.sorted { $0.receivedAt > $1.receivedAt }.prefix(100))
    }
}
