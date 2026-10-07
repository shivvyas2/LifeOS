import Foundation
import FoundationModels
import Integrations
import Insights

@Generable
struct MailVerdictModel {
    @Generable
    enum Bucket { case needsYou, fyi }

    @Guide(description: "needsYou if the sender asks the reader to reply, decide, sign, pay, attend or meet a deadline; otherwise fyi")
    var bucket: Bucket
    @Guide(description: "One plain sentence, at most 90 characters, saying what the mail wants or says")
    var summary: String
}

/// Sorts mail into NEEDS YOU and FYI with Apple's on-device model. Each
/// message is judged once; without the model, or when a call fails, it is
/// FYI with Gmail's snippet.
struct MailSorter {
    var isModelAvailable: @Sendable () -> Bool = {
        ModelAvailability.from(SystemLanguageModel.default.availability) == .available
    }

    func verdicts(for items: [MailItem], cache: MailVerdictCache) async -> [String: MailVerdict] {
        var verdicts: [String: MailVerdict] = [:]
        var unjudged: [MailItem] = []
        for item in items {
            if let known = cache.verdict(for: item.id) { verdicts[item.id] = known } else { unjudged.append(item) }
        }
        guard !unjudged.isEmpty else { return verdicts }
        guard isModelAvailable() else {
            // Not cached: the model may be ready next time.
            for item in unjudged { verdicts[item.id] = MailFallback.verdict(for: item) }
            return verdicts
        }
        let instructions = """
        You sort a person's email. For each mail, decide whether it needs them to act, and say in one short \
        sentence what it wants or says. Use only what is given.
        """
        for item in unjudged {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "From: \(item.sender)\nSubject: \(item.subject)\nPreview: \(item.snippet)"
            if let answer = try? await session.respond(to: prompt, generating: MailVerdictModel.self).content {
                let summary = MailFallback.trimmed(answer.summary)
                let verdict = MailVerdict(bucket: answer.bucket == .needsYou ? .needsYou : .fyi,
                                          summary: summary.isEmpty ? MailFallback.verdict(for: item).summary : summary)
                cache.store(verdict, for: item.id)
                verdicts[item.id] = verdict
            } else {
                verdicts[item.id] = MailFallback.verdict(for: item)
            }
        }
        return verdicts
    }
}
