import UIKit
import LinkKit

/// What came back from the bank login.
enum PlaidLinkResult {
    case connected(publicToken: String, institutionID: String?, institutionName: String?)
    /// The user backed out. Not an error and not worth an alert.
    case cancelled
    case failed(String)
}

/// Presents Plaid's Link flow.
///
/// The only file in the app that imports LinkKit. Keeping the SDK behind this
/// one seam means the connection view model is testable against `PlaidAPI`
/// alone, and swapping presentation later touches nothing else.
@MainActor
enum PlaidLinkPresenter {
    static func present(linkToken: String, completion: @escaping (PlaidLinkResult) -> Void) {
        var configuration = LinkTokenConfiguration(token: linkToken) { success in
            completion(.connected(
                publicToken: success.publicToken,
                institutionID: success.metadata.institution.id,
                institutionName: success.metadata.institution.name
            ))
        }
        configuration.onExit = { exit in
            // A user closing the sheet is the common path here, so an exit with
            // no error must not be dressed up as a failure.
            if let error = exit.error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(.cancelled)
            }
        }

        switch Plaid.create(configuration) {
        case .failure(let error):
            completion(.failed(error.localizedDescription))
        case .success(let handler):
            guard let controller = topViewController() else {
                completion(.failed("No window to present from"))
                return
            }
            handler.open(presentUsing: .viewController(controller))
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
