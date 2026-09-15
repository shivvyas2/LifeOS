import SwiftUI
import AppSurfaces

/// A HUD the person can put anywhere over the player, and that stays there.
///
/// The rings follow the finger while dragging and settle on release: inside
/// the container, and off the strip along the bottom where YouTube's control
/// bar and logo live. Where they settle is kept per placement, so the rings
/// over the small portrait player, the full screen player and the landscape
/// player each remember their own spot, and it survives the HUD collapsing
/// to the bar because what is stored is a fraction of the free travel rather
/// than a point.
struct DraggableHUD<Content: View>: View {
    /// Which placement's position this is: the small player, full screen or
    /// landscape.
    let placement: String
    var inset: CGFloat = VideoWorkoutLayout.overlayInset
    /// The rect the HUD may not rest on, in the container's coordinates,
    /// derived from the container's size.
    var avoiding: (CGSize) -> CGRect? = { _ in nil }
    @ViewBuilder let content: () -> Content

    @AppStorage private var stored: String
    @State private var hudSize = CGSize.zero
    @State private var containerSize = CGSize.zero
    @State private var origin: CGPoint?
    @State private var drag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(placement: String, inset: CGFloat = VideoWorkoutLayout.overlayInset,
         avoiding: @escaping (CGSize) -> CGRect? = { _ in nil },
         @ViewBuilder content: @escaping () -> Content) {
        self.placement = placement
        self.inset = inset
        self.avoiding = avoiding
        self.content = content
        _stored = AppStorage(wrappedValue: "", "videoHUD.anchor.\(placement)")
    }

    private var anchor: HUDPlacement.Anchor { HUDPlacement.Anchor(stored: stored) ?? .topLeading }

    var body: some View {
        // A GeometryReader, because it is the one container that puts its
        // child at the top leading corner without being asked, which makes
        // the offset below the HUD's actual origin.
        GeometryReader { proxy in
            content()
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    hudSize = size
                    place(animated: origin != nil)
                }
                .offset(x: (origin?.x ?? inset) + drag.width, y: (origin?.y ?? inset) + drag.height)
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            let dropped = CGPoint(x: (origin?.x ?? inset) + value.translation.width,
                                                  y: (origin?.y ?? inset) + value.translation.height)
                            let settled = HUDPlacement.settle(origin: dropped, hud: hudSize, container: containerSize,
                                                              inset: inset, avoiding: avoiding(containerSize))
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2)) {
                                drag = .zero
                                origin = settled
                            }
                            stored = HUDPlacement.anchor(for: settled, hud: hudSize, container: containerSize,
                                                         inset: inset).stored
                        }
                )
                .accessibilityAction(named: "Move to top left") { move(to: .topLeading) }
                .accessibilityAction(named: "Move to top right") { move(to: .init(x: 1, y: 0)) }
                .accessibilityAction(named: "Move to bottom left") { move(to: .init(x: 0, y: 1)) }
                .accessibilityAction(named: "Move to bottom right") { move(to: .init(x: 1, y: 1)) }
                // Nothing until it has been measured: a HUD drawn at the
                // inset for one frame and then jumping to its saved spot
                // reads as a glitch on every appearance.
                .opacity(origin == nil ? 0 : 1)
                .onChange(of: proxy.size, initial: true) { _, size in
                    containerSize = size
                    place(animated: false)
                }
        }
    }

    /// Puts the HUD at its saved anchor for the current sizes. Run again
    /// whenever either size changes, so a rotation or a collapse keeps the
    /// rings in the same relative place and never off screen.
    private func place(animated: Bool) {
        guard hudSize != .zero, containerSize != .zero else { return }
        let wanted = HUDPlacement.origin(for: anchor, hud: hudSize, container: containerSize, inset: inset)
        let settled = HUDPlacement.settle(origin: wanted, hud: hudSize, container: containerSize,
                                          inset: inset, avoiding: avoiding(containerSize))
        guard settled != origin else { return }
        withAnimation(animated && !reduceMotion ? .spring(duration: 0.35, bounce: 0.15) : nil) {
            origin = settled
        }
    }

    private func move(to anchor: HUDPlacement.Anchor) {
        stored = anchor.stored
        place(animated: true)
    }
}
