import Foundation
import Persistence

/// One choice, and what it is worth on the shared scale.
public struct CheckInOption: Sendable, Equatable {
    public let label: String
    public let normalised: Double

    public init(_ label: String, _ normalised: Double) {
        self.label = label
        self.normalised = normalised
    }
}

/// A question asked at close time for a sector with no tracked data.
///
/// `id` is written to `CheckInAnswer` and compared against next month, so ids
/// are append-only in exactly the way `LifeSector`'s raw values are. Renaming
/// one orphans every answer already stored against it.
public struct CheckInQuestion: Sendable, Equatable {
    public let id: String
    public let prompt: String
    /// Empty means free text: recorded as context, never scored.
    public let options: [CheckInOption]
    public let weight: Double

    public init(id: String, prompt: String, options: [CheckInOption], weight: Double = 1) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.weight = weight
    }

    public var isFreeText: Bool { options.isEmpty }

    private static let scale: [CheckInOption] = [
        CheckInOption("barely", 0.0),
        CheckInOption("some", 0.35),
        CheckInOption("a fair amount", 0.7),
        CheckInOption("a lot", 1.0),
    ]

    public static func questions(for sector: LifeSector) -> [CheckInQuestion] {
        switch sector {
        case .family:
            [
                CheckInQuestion(id: "family.contact", prompt: "How much did you speak with family?", options: scale, weight: 2),
                CheckInQuestion(id: "family.showedUp", prompt: "Were you there when it mattered?", options: [
                    CheckInOption("no", 0.0), CheckInOption("once or twice", 0.5), CheckInOption("yes", 1.0),
                ], weight: 2),
                CheckInQuestion(id: "family.note", prompt: "One thing worth remembering", options: []),
            ]
        case .romance:
            [
                CheckInQuestion(id: "romance.state", prompt: "Where are things?", options: [
                    CheckInOption("alone, and not looking", 0.5),
                    CheckInOption("alone, and looking", 0.3),
                    CheckInOption("seeing someone", 0.7),
                    CheckInOption("together", 1.0),
                ], weight: 1),
                CheckInQuestion(id: "romance.time", prompt: "Time together felt", options: [
                    CheckInOption("too little", 0.2), CheckInOption("about right", 0.8), CheckInOption("plenty", 1.0),
                ], weight: 2),
                CheckInQuestion(id: "romance.note", prompt: "One thing worth remembering", options: []),
            ]
        case .friends:
            [
                CheckInQuestion(id: "friends.seen", prompt: "How often did you see friends?", options: scale, weight: 2),
                CheckInQuestion(id: "friends.depth", prompt: "Did any of it go beyond small talk?", options: [
                    CheckInOption("no", 0.0), CheckInOption("once", 0.5), CheckInOption("more than once", 1.0),
                ], weight: 2),
                CheckInQuestion(id: "friends.note", prompt: "Who is worth calling next month?", options: []),
            ]
        case .soul:
            [
                CheckInQuestion(id: "soul.settled", prompt: "How settled did you feel?", options: scale, weight: 2),
                CheckInQuestion(id: "soul.note", prompt: "One thing worth remembering", options: []),
            ]
        case .mind:
            [
                CheckInQuestion(id: "mind.clarity", prompt: "How clear was your head?", options: scale, weight: 2),
            ]
        case .growth, .money, .mission, .body:
            []
        }
    }
}
