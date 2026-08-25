import Persistence

/// When a close should ask the on-device model for a fresh sector note, and
/// whether a note that comes back is still safe to show.
public enum NoteRequest {
    /// Whether newly computed evidence should trigger a fresh note request.
    ///
    /// Fires only on the transition from no evidence to some evidence for the
    /// sector on screen. A sector appears before it has any evidence at all
    /// for a check-in-fed sector (nothing has been answered yet), so asking
    /// on appearance asks about nothing. The rows only exist once an answer
    /// or a data-fed proposal produces one, which is the point this fires.
    /// Because it only fires on that one transition, answering a second
    /// question or editing free text afterwards does not fire again: the
    /// evidence is already non-empty, so there is nothing left to transition
    /// into.
    public static func shouldRequest(wasEmpty: Bool, isEmptyNow: Bool) -> Bool {
        wasEmpty && !isEmptyNow
    }

    /// Whether a note that just came back is still safe to apply.
    ///
    /// A request in flight when the close advances to the next sector must
    /// not write its sentence over the new sector's, even though the sector
    /// it was asked about no longer matches what is on screen by the time it
    /// resolves.
    public static func shouldApply(resultSector: LifeSector, currentSector: LifeSector?) -> Bool {
        currentSector == resultSector
    }
}
