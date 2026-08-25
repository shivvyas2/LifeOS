/// What `chosenScore` should read after a close recomputes its proposal.
///
/// The close recomputes on every answer, including one keystroke at a time
/// into a free-text field, so this has to run far more often than the person
/// actually touches the score stepper. Before they touch it, the seed should
/// track the best available suggestion, so answering a check-in question
/// updates the number shown. The moment they touch it themselves, their pick
/// is authoritative: the spec's first decision is that the user's number is
/// what gets stored, so no later recompute may replace it, however small the
/// change that triggered the recompute.
public enum ChosenScore {
    /// - Parameters:
    ///   - current: What `chosenScore` currently reads.
    ///   - hasChosen: Whether the person has touched the stepper for the
    ///     sector on screen since it was presented.
    ///   - proposed: The rule's current proposal, if it has one.
    ///   - previousUserScore: What the person scored this sector last month.
    public static func seeded(
        current: Int, hasChosen: Bool, proposed: Int?, previousUserScore: Int?
    ) -> Int {
        hasChosen ? current : (proposed ?? previousUserScore ?? 5)
    }
}
