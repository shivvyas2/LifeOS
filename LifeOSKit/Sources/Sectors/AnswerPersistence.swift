/// Whether an answer to a check-in question should be written to the store
/// the moment it is given, or held briefly in case more is coming.
///
/// A choice button is one discrete event: saving it immediately is one
/// `context.save()`, which is the cost every other write in the app already
/// pays. Free text is a stream of keystrokes; saving every one of them fires
/// a `context.save()` per character, and `RootView` turns every save into a
/// `reloadAll()` across nine view models. The view model debounces free text
/// instead, saving once the person pauses rather than once per character.
public enum AnswerPersistence {
    public static func isImmediate(_ question: CheckInQuestion) -> Bool {
        !question.isFreeText
    }
}
