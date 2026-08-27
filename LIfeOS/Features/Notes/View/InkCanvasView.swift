import SwiftUI
import PencilKit

/// The ink layer over a page: annotation, not content.
///
/// Sits above the blocks so a mark can be made around the words it belongs to,
/// and claims touches only while ink mode is on. That last part matters more
/// than it sounds.
///
/// It used to claim every Pencil touch, on the theory that picking the Pencil
/// up should mean drawing. The cost was hidden and larger than the benefit:
/// a `UITextView` gets Scribble free, so a Pencil over a paragraph should turn
/// handwriting into text, and a layer that swallowed the touch first meant
/// Scribble could never fire anywhere in the app. Sketch blocks would have been
/// unreachable for the same reason.
///
/// So the rule is stated by where the Pencil is, not by what it is:
///
///   - Over a text block, a Pencil writes. Handwriting becomes text.
///   - Over a sketch block, a Pencil draws in that block.
///   - With ink mode on, a Pencil annotates the whole page, and so does a
///     finger.
///
/// Double-tapping or squeezing the Pencil turns ink mode on, so the annotation
/// layer is one gesture away without a trip to the toolbar.
struct InkCanvasView: UIViewRepresentable {
    @Binding var data: Data?
    /// True when the ink button is on: everything draws, including a finger.
    let isInkMode: Bool
    /// Raised by a Pencil double-tap or squeeze.
    var onPencilShortcut: () -> Void
    /// The height of the page's blocks, so the canvas covers exactly the
    /// content and a stroke stays next to the line it was drawn beside.
    let height: CGFloat
    let isDark: Bool

    func makeUIView(context: Context) -> PassthroughCanvasView {
        let canvas = PassthroughCanvasView()
        // Double-tap and squeeze. Both are set up here rather than on each
        // sketch block: the gesture is a property of the Pencil, not of
        // whatever it happens to be hovering over, and two interactions on
        // overlapping views would fire twice.
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)
        canvas.onPencilShortcut = { onPencilShortcut() }
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false          // the page's own scroll view owns scrolling
        canvas.alwaysBounceVertical = false
        // The adaptive part. A Pencil always draws, whatever mode the page is
        // in, so on an iPad you pick the Pencil up and write; a finger keeps
        // typing and scrolling until the ink button says otherwise.
        canvas.drawingPolicy = .pencilOnly
        canvas.isInkMode = isInkMode

        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PassthroughCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isInkMode = isInkMode
        canvas.drawingPolicy = isInkMode ? .anyInput : .pencilOnly

        // Only reload when the bytes differ, since assigning a drawing resets
        // the undo stack and interrupts a stroke in progress.
        if let data, data != context.coordinator.lastWritten,
           let drawing = try? PKDrawing(data: data), drawing != canvas.drawing {
            canvas.drawing = drawing
        }
        if data == nil, !canvas.drawing.strokes.isEmpty, context.coordinator.lastWritten != nil {
            canvas.drawing = PKDrawing()
        }

        // Ink drawn in black on a dark page would be invisible. PencilKit's own
        // inversion handles the strokes; this keeps the picker in step.
        canvas.overrideUserInterfaceStyle = isDark ? .dark : .light

        context.coordinator.setPickerVisible(isInkMode, on: canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: InkCanvasView
        weak var canvas: PassthroughCanvasView?
        var lastWritten: Data?

        init(_ parent: InkCanvasView) { self.parent = parent }

        func setPickerVisible(_ visible: Bool, on canvas: PassthroughCanvasView) {
            if visible {
                NoteToolPicker.shared.show(for: canvas)
            } else {
                NoteToolPicker.shared.hide(for: canvas)
            }
        }

        // MARK: Pencil

        /// Double-tap. Turns ink mode on when it is off, because reaching for
        /// the toolbar to start annotating is the friction the gesture exists
        /// to remove. Once annotating, it does what it does everywhere else and
        /// swaps the eraser in and out.
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveTap tap: UIPencilInteraction.Tap
        ) {
            if parent.isInkMode {
                NoteToolPicker.shared.toggleEraser()
            } else {
                parent.onPencilShortcut()
            }
        }

        /// Squeeze, on the Pencil Pro. Toggles the annotation layer outright,
        /// so the same squeeze that starts a mark ends it.
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard squeeze.phase == .ended else { return }
            parent.onPencilShortcut()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // An empty drawing is stored as nil rather than as an empty
            // PKDrawing, so "has ink" stays a single question with a single
            // answer everywhere it is asked.
            let data = canvasView.drawing.strokes.isEmpty ? nil : canvasView.drawing.dataRepresentation()
            lastWritten = data
            parent.data = data
        }
    }
}

/// A canvas that only claims the touches it should.
///
/// The canvas is a scroll view, so even with `drawingPolicy = .pencilOnly` it
/// swallows touches the text underneath needs. Hit testing decides who gets
/// them, and the answer is: nobody but ink mode.
final class PassthroughCanvasView: PKCanvasView {
    var isInkMode = false
    /// Called when the Pencil is double-tapped or squeezed. Set by the
    /// representable, so the gesture reaches SwiftUI state.
    var onPencilShortcut: (() -> Void)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Transparent to everything unless ink mode is on. Anything else and
        // this layer sits between the Pencil and the text it is trying to
        // write into. See the type comment above.
        guard isInkMode else { return false }
        return super.point(inside: point, with: event)
    }
}
