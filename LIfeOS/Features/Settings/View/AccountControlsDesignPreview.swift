#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// The account controls without a server: `--page=settings-clear-data`,
/// `settings-delete-account` and `keep-account`.
struct AccountControlsDesignPreview: View {
    let page: String
    @State private var container = try! LifeOSContainer.make(inMemory: true)
    @State private var kept = false

    var body: some View {
        switch page {
        case "settings-clear-data":
            NavigationStack { ClearDataScreen(client: StubAccountDataClient()) }
                .modelContainer(container)
        case "settings-delete-account":
            NavigationStack { DeleteAccountScreen(client: StubAccountDataClient()) }
        default:
            if kept {
                Text("Kept").font(LifeOSType.screenTitle).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                KeepAccountScreen(date: Calendar.current.date(byAdding: .day, value: 23, to: .now)!,
                                  onKeep: { kept = true }, onSignOut: {})
            }
        }
    }
}

/// Answers at once, as though the server agreed.
struct StubAccountDataClient: AccountDataClienting {
    func clear(_ categories: Set<DataCategory>) async throws {}
    func scheduleDeletion() async throws -> Date { .now.addingTimeInterval(30 * 86_400) }
    func keep() async throws {}
    func scheduledDeletion() async throws -> Date? { nil }
    func deleted(among ids: [String]) async throws -> [String] { [] }
}
#endif
