import PencilKit

/// The one tool picker, shared by the page's ink layer and every sketch block.
///
/// `PKToolPicker` is a floating palette the system positions, and two of them
/// fight: whichever became visible last wins, and the loser leaves a stale
/// observer behind that keeps receiving tool changes for a canvas nobody is
/// drawing in. One instance, handed to whichever canvas is first responder.
@MainActor
final class NoteToolPicker {
    static let shared = NoteToolPicker()

    let picker = PKToolPicker()
    /// Canvases already observing, so a view that updates twenty times does not
    /// register twenty observers. PencilKit keeps duplicates rather than
    /// ignoring them.
    private var observing = Set<ObjectIdentifier>()

    private init() {}

    func show(for canvas: PKCanvasView) {
        register(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        if !canvas.isFirstResponder {
            canvas.becomeFirstResponder()
        }
    }

    func hide(for canvas: PKCanvasView) {
        picker.setVisible(false, forFirstResponder: canvas)
        if canvas.isFirstResponder {
            canvas.resignFirstResponder()
        }
    }

    func release(_ canvas: PKCanvasView) {
        hide(for: canvas)
        picker.removeObserver(canvas)
        observing.remove(ObjectIdentifier(canvas))
    }

    private func register(_ canvas: PKCanvasView) {
        let key = ObjectIdentifier(canvas)
        guard !observing.contains(key) else { return }
        picker.addObserver(canvas)
        observing.insert(key)
    }

    /// Swaps between the current tool and the eraser, which is what a Pencil
    /// double-tap does in every drawing app worth using.
    func toggleEraser() {
        if picker.selectedTool is PKEraserTool {
            picker.selectedTool = previousTool ?? PKInkingTool(.pen, color: .label, width: 4)
        } else {
            previousTool = picker.selectedTool
            picker.selectedTool = PKEraserTool(.bitmap)
        }
    }

    private var previousTool: PKTool?
}
