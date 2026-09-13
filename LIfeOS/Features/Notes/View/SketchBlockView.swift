import SwiftUI
import PencilKit
import DesignSystem
import Persistence

/// A drawing that takes its own space in the document.
///
/// Distinct from the page's ink layer on purpose. The ink layer floats over
/// everything and is for annotating what is already written; a sketch block
/// sits in the flow, pushes the text below it down, and moves with the
/// paragraph it belongs to. A diagram between two paragraphs wants the second
/// behaviour, and no amount of layered annotation gives it.
struct SketchBlockView: View {
    let block: NoteBlock
    var onDrawing: (Data?) -> Void
    var onHeight: (Double) -> Void

    @Environment(\.colorScheme) private var scheme
    /// Pencil-only by default so a finger still scrolls the page past the
    /// sketch. A person without a Pencil turns this on and draws with a finger.
    @State private var acceptsFinger = false
    @State private var isActive = false
    @State private var dragHeight: Double?
    @State private var confirmClear = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var height: Double { dragHeight ?? block.resolvedSketchHeight }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                BlockCanvasView(
                    drawing: block.drawing,
                    acceptsFinger: acceptsFinger,
                    isActive: isActive,
                    isDark: scheme == .dark,
                    onDrawing: onDrawing,
                    onActivate: { isActive = true }
                )
                .frame(height: height)

                if block.isBlankSketch, !isActive {
                    prompt
                }

                controls
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(scheme == .dark ? 0.07 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? LifeOSTokens.accent.opacity(0.5)
                                    : LifeOSTokens.primaryText.resolve(scheme).opacity(0.08),
                                lineWidth: isActive ? 2 : 1
                            )
                    )
            )

            resizeHandle
        }
        .padding(.vertical, 6)
        .onAppear { acceptsFinger = sizeClass == .compact }
        .confirmationDialog("Clear this sketch?", isPresented: $confirmClear) {
            Button("Clear sketch", role: .destructive) { onDrawing(nil) }
        }
    }

    private var prompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "scribble.variable")
                .font(LifeOSType.sectionTitle)
            Text(acceptsFinger ? "Draw here" : "Draw here with a pencil")
                .font(LifeOSType.label)
        }
        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button {
                acceptsFinger.toggle()
            } label: {
                Image(systemName: acceptsFinger ? "hand.draw.fill" : "hand.draw")
                    .font(LifeOSType.caption.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(acceptsFinger ? "Draw with pencil only" : "Draw with a finger too")

            if !block.isBlankSketch {
                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "eraser")
                        .font(LifeOSType.caption.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear sketch")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(LifeOSTokens.cardSurface.resolve(scheme)))
        .padding(6)
        .hoverEffect(.highlight)
    }

    /// Dragged, not typed. The committed height only lands when the gesture
    /// ends, so a resize in progress does not write to the document on every
    /// frame and mark it dirty forty times.
    private var resizeHandle: some View {
        Capsule()
            .fill(LifeOSTokens.secondaryText.resolve(scheme).opacity(0.35))
            .frame(width: 40, height: 4)
            .padding(.vertical, 6)
            .contentShape(.rect)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragHeight = min(
                            max(block.resolvedSketchHeight + value.translation.height,
                                NoteBlock.minSketchHeight),
                            NoteBlock.maxSketchHeight
                        )
                    }
                    .onEnded { _ in
                        if let dragHeight { onHeight(dragHeight) }
                        dragHeight = nil
                    }
            )
            .hoverEffect(.highlight)
            .accessibilityLabel("Resize sketch")
    }
}

/// The canvas inside one sketch block.
private struct BlockCanvasView: UIViewRepresentable {
    let drawing: Data?
    let acceptsFinger: Bool
    let isActive: Bool
    let isDark: Bool
    var onDrawing: (Data?) -> Void
    var onActivate: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Its own scrolling is off: the page's scroll view owns that, and a
        // canvas that scrolls inside a scrolling page traps the gesture.
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = acceptsFinger ? .anyInput : .pencilOnly
        if let drawing, let decoded = try? PKDrawing(data: drawing) {
            canvas.drawing = decoded
        }
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.drawingPolicy = acceptsFinger ? .anyInput : .pencilOnly
        canvas.overrideUserInterfaceStyle = isDark ? .dark : .light

        // Only reload when the bytes actually differ, since assigning a drawing
        // resets the undo stack and interrupts a stroke in progress.
        if let drawing, drawing != context.coordinator.lastWritten,
           let decoded = try? PKDrawing(data: drawing), decoded != canvas.drawing {
            canvas.drawing = decoded
        }
        if drawing == nil, !canvas.drawing.strokes.isEmpty {
            canvas.drawing = PKDrawing()
            context.coordinator.lastWritten = nil
        }

        if isActive != context.coordinator.wasActive {
            context.coordinator.wasActive = isActive
            if isActive { NoteToolPicker.shared.show(for: canvas) }
            else { NoteToolPicker.shared.hide(for: canvas) }
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        NoteToolPicker.shared.release(canvas)
        canvas.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: BlockCanvasView
        weak var canvas: PKCanvasView?
        var lastWritten: Data?
        var wasActive = false

        init(_ parent: BlockCanvasView) { self.parent = parent }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            NoteToolPicker.shared.show(for: canvasView)
            parent.onActivate()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data = canvasView.drawing.strokes.isEmpty
                ? nil
                : canvasView.drawing.dataRepresentation()
            lastWritten = data
            parent.onDrawing(data)
        }
    }
}
