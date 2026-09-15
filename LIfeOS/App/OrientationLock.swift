import UIKit

/// Which way the app may turn, decided per screen.
///
/// The iPhone target allows landscape in its build settings so that a
/// workout video can be watched sideways, but almost nothing else in the app
/// is laid out for it. So the default here is portrait on a phone, and the
/// one screen that wants more asks for it while it is on screen and hands it
/// back when it leaves. iPad keeps every orientation, as it always has.
@MainActor
enum OrientationLock {
    static let standard: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    /// Read by the app delegate on every orientation query.
    private(set) static var mask = standard

    static func allow(_ allowed: UIInterfaceOrientationMask) {
        guard mask != allowed else { return }
        mask = allowed
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    /// Back to the default, and back upright: a phone still held sideways
    /// would otherwise stay in a landscape the next screen cannot draw.
    static func release() {
        allow(standard)
        guard standard == .portrait else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }
}
