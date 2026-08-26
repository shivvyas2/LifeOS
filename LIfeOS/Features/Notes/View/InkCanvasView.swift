import SwiftUI
import PencilKit

/// The ink layer over a page.
///
/// Sits above the blocks rather than beside them, so a diagram can be drawn
/// around the words it belongs to. That only works if the layer knows when to
/// get out of the way, which is what `PassthroughCanvasView` below decides.
struct InkCanvasView: UIViewRepresentable {
    @Binding var data: Data?
    /// True when the ink button is on: everything draws, including a finger.
    let isInkMode: Bool
    /// The height of the page's blocks, so the canvas covers exactly the
    /// content and a stroke stays next to the line it was drawn beside.
    let height: CGFloat
    let isDark: Bool

    func makeUIView(context: Context) -> PassthroughCanvasView {
        let canvas = PassthroughCanvasView()
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

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvasView
        weak var canvas: PassthroughCanvasView?
        var lastWritten: Data?
        private var isObserving = false
        private let picker = PKToolPicker()

        init(_ parent: InkCanvasView) { self.parent = parent }

        func setPickerVisible(_ visible: Bool, on canvas: PassthroughCanvasView) {
            picker.setVisible(visible, forFirstResponder: canvas)
            // Registered once. `updateUIView` runs on every state change, and
            // PencilKit keeps duplicate observers rather than ignoring them.
            if !isObserving {
                picker.addObserver(canvas)
                isObserving = true
            }
            if visible, !canvas.isFirstResponder {
                DispatchQueue.main.async { canvas.becomeFirstResponder() }
            } else if !visible, canvas.isFirstResponder {
                DispatchQueue.main.async { canvas.resignFirstResponder() }
            }
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
/// `drawingPolicy = .pencilOnly` stops a finger *drawing*, but the canvas is a
/// scroll view and still swallows the touch, so the text underneath would never
/// see a tap. Deciding hit testing by touch type is what lets ink and text
/// share the same rectangle.
final class PassthroughCanvasView: PKCanvasView {
    var isInkMode = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        // In ink mode the layer is on top of everything on purpose.
        if isInkMode { return true }
        // Otherwise only a Pencil is ours. A touch with no type information at
        // all is treated as a finger: letting an unknown touch draw would make
        // the page unusable, while letting it type never can.
        guard let touch = event?.allTouches?.first else { return false }
        return touch.type == .pencil
    }
}
