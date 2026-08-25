import Testing
@testable import Sectors

@Suite struct AnswerPersistenceTests {

    @Test func aChoiceQuestionSavesImmediately() {
        let question = CheckInQuestion(
            id: "friends.seen", prompt: "How often did you see friends?",
            options: [CheckInOption("a lot", 1.0)]
        )
        #expect(AnswerPersistence.isImmediate(question))
    }

    @Test func aFreeTextQuestionDoesNotSaveImmediately() {
        let question = CheckInQuestion(id: "family.note", prompt: "One thing worth remembering", options: [])
        #expect(!AnswerPersistence.isImmediate(question))
    }
}
