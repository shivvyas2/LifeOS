// LifeOSKit/Sources/Assistant/ToolDates.swift
import Foundation

enum ToolDateError: Error, LocalizedError {
    case unparseable(String)

    var errorDescription: String? {
        switch self {
        case .unparseable(let raw):
            "\(raw) is not an ISO-8601 date. Use e.g. 2026-08-26T09:00:00Z."
        }
    }
}

enum ToolDates {
    // ISO8601DateFormatter isn't Sendable, but this instance is configured
    // once and only ever read (never mutated) after that, from any thread;
    // `nonisolated(unsafe)` documents that instead of caching a formatter
    // per call.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) throws -> Date {
        guard let date = formatter.date(from: raw) else {
            throw ToolDateError.unparseable(raw)
        }
        return date
    }

    static func render(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE MMM d HH:mm"
        return formatter.string(from: date)
    }
}
