# LifeOS Focus App Target (Slice 3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the LifeOS Focus iOS app to `LIfeOS.xcodeproj` as a target that
builds, signs in with the shared LifeOS account ("Continue as" or a code),
keeps the session across launches, and opens a starter Home.

**Architecture:**
- **The account gate.** Session handling (restore, save, sign out) lives in a
  new `AccountGate` in `AccountUI`, so it is unit-tested in the package. Each
  app persists its own session through it, which is what the slice 1 ruling
  requires: `SignInModel` deliberately does not save sessions itself.
- **The target.** A Ruby script built on the `xcodeproj` gem creates the
  target, its synchronized source folder, its package products and a shared
  scheme. That keeps the `project.pbxproj` change reproducible instead of
  hand-edited.
- **Deferred.** Moving the Focus code, the watch app and the widget are
  slices 3b and 3c.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, `xcodeproj` Ruby gem 1.27,
xcodebuild, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-10-lifeos-focus-app-design.md`
(section 1, Targets; section 3, First run).

## Global Constraints

- Target `LifeOSFocus`, an iOS app, with bundle id `com.shivvyas.lifeos.focus`, team `Z42YU5W6WY`, iOS 26.0, iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- Display name: "LifeOS Focus".
- The same editorial look as LifeOS: `DesignSystem` tokens only, and no literal font sizes or Apple semantic text styles (`scripts/check-typography.sh`).
- Shared Keychain group `$(AppIdentifierPrefix)com.shivvyas.lifeos.shared`. It is listed second, after the app's own group `$(AppIdentifierPrefix)com.shivvyas.lifeos.focus`.
- `SharedSignIn.accessGroup = "Z42YU5W6WY.com.shivvyas.lifeos.shared"` is set at launch.
- Secrets come from `Config/Secrets.xcconfig` (`SUPABASE_URL` and `SUPABASE_ANON_KEY`) through the target's Info.plist. CI copies `Secrets.example.xcconfig` over it.
- No AI attribution in commits, no em dashes, and conventional commits. Work on branch `feat/focus-app`, stacked on `feat/focus-sync`.
- A new UI test file needs four pbxproj entries. This slice adds no UI test target.

## Review Focus

1. **A stored session the server refuses.** On launch it must land on sign-in with "Your session expired. Sign in again", not on Home with a dead token. Test: Task 1 `aRefusedSessionSignsOutWithAMessage`.
2. **The session cannot be saved after sign-in (Keychain error).** The app must stay on sign-in with an error, not show Home with nothing persisted. This is the slice 2 deferred minor, fixed here for Focus. Test: Task 1 `aSessionThatCannotBeSavedStaysSignedOut`.
3. **Offline at launch with a valid stored session.** The app must open Home, because `SessionRefresher` keeps the session on transport errors. Test: Task 1 `restoreKeepsAnActiveSession`.
4. **Sign out, then sign in again in the same launch.** The code flow must start clean: on the identity step, with no stale code or error. Test: Task 1 `signOutStartsAFreshSignIn`.
5. **A build with blank secrets (CI).** It must compile and show the "Sign-in is unavailable" copy, not crash. Covered by Task 4's CI build with `Secrets.example.xcconfig`, and by `SignInModel.isConfigured` (already tested).

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `LifeOSKit/Sources/AccountUI/AccountGate.swift` | Create | Holds the session: restore on launch, persist on sign-in, sign out |
| `LifeOSKit/Tests/AccountUITests/AccountGateTests.swift` | Create | The gate's behaviour |
| `LifeOSKit/Tests/AccountUITests/SignInModelTests.swift` | Modify | `FakeBackend.restoreOutcome` becomes configurable |
| `scripts/add-focus-target.rb` | Create | Creates the target, its sources, products, settings and scheme. Safe to re-run |
| `LifeOSFocus/LifeOSFocusApp.swift` | Create | `@main`, beacon group, root view |
| `LifeOSFocus/FocusConfig.swift` | Create | Supabase URL and anon key from Info.plist |
| `LifeOSFocus/FocusRootView.swift` | Create | Sign-in or Home, from the gate |
| `LifeOSFocus/FocusHomeView.swift` | Create | Starter Home: masthead, account, sign out |
| `LifeOSFocus/Info.plist` | Create | `SupabaseURL` and `SupabaseAnonKey` from the xcconfig |
| `LifeOSFocus/LifeOSFocus.entitlements` | Create | Keychain groups |
| `LIfeOS.xcodeproj/project.pbxproj`, `LIfeOS.xcodeproj/xcshareddata/xcschemes/LifeOSFocus.xcscheme` | Generated | By the script |
| `.github/workflows/ci.yml` | Modify | Also build the `LifeOSFocus` scheme |

---

### Task 1: `AccountGate`

**Files:**
- Create: `LifeOSKit/Sources/AccountUI/AccountGate.swift`
- Modify: `LifeOSKit/Tests/AccountUITests/SignInModelTests.swift` (`FakeBackend`)
- Test: `LifeOSKit/Tests/AccountUITests/AccountGateTests.swift`

**Interfaces:**
- Consumes:
  - `SignInModel(backend:store:onSignedIn:)` and `SignInModel.report(_:)`
  - `SignInBackend.restore(store:) -> SessionRefresher.Outcome`, which is
    `.active(AuthSession)`, `.signedOut` or `.rejected`
  - `AuthSessionStoring`
- Produces: `@MainActor @Observable public final class AccountGate`, with:
  - `public init(backend: (any SignInBackend)?, store: any AuthSessionStoring)`
  - `public private(set) var session: AuthSession?`
  - `public var isSignedIn: Bool`
  - `public private(set) var signIn: SignInModel`
  - `public func restore() async`
  - `public func signOut()`

- [ ] **Step 1: Make the fake's restore configurable**

In `SignInModelTests.swift`, inside `FakeBackend`, replace
`func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome { .signedOut }`
with:

```swift
    var restoreOutcome: SessionRefresher.Outcome = .signedOut
    func restore(store: any AuthSessionStoring) async -> SessionRefresher.Outcome { restoreOutcome }
```

- [ ] **Step 2: Write the failing tests**

```swift
// LifeOSKit/Tests/AccountUITests/AccountGateTests.swift
import Testing
import Foundation
import Integrations
@testable import AccountUI

final class FailingStore: AuthSessionStoring, @unchecked Sendable {
    func load() -> AuthSession? { nil }
    func save(_ session: AuthSession) throws { throw AuthStoreError.keychain(-34018) }
    func clear() {}
}

@MainActor
struct AccountGateTests {
    @Test func verifyingPersistsTheSessionAndSignsIn() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let store = InMemoryAuthSessionStore()
        let gate = AccountGate(backend: backend, store: store)
        gate.signIn.draft.code = "123456"
        await gate.signIn.verifyCode()
        #expect(gate.isSignedIn)
        #expect(store.load()?.userID == "u1")
    }

    @Test func aSessionThatCannotBeSavedStaysSignedOut() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let gate = AccountGate(backend: backend, store: FailingStore())
        gate.signIn.draft.code = "123456"
        await gate.signIn.verifyCode()
        #expect(!gate.isSignedIn)
        #expect(gate.signIn.errorMessage != nil)
    }

    @Test func restoreKeepsAnActiveSession() async {
        let backend = FakeBackend()
        backend.restoreOutcome = .active(.sample())
        let gate = AccountGate(backend: backend, store: InMemoryAuthSessionStore())
        await gate.restore()
        #expect(gate.session?.userID == "u1")
    }

    @Test func aRefusedSessionSignsOutWithAMessage() async {
        let backend = FakeBackend()
        backend.restoreOutcome = .rejected
        let store = InMemoryAuthSessionStore(session: .sample())
        let gate = AccountGate(backend: backend, store: store)
        await gate.restore()
        #expect(!gate.isSignedIn)
        #expect(store.load() == nil)
        #expect(gate.signIn.errorMessage == "Your session expired. Sign in again")
    }

    @Test func signOutStartsAFreshSignIn() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let store = InMemoryAuthSessionStore()
        let gate = AccountGate(backend: backend, store: store)
        gate.signIn.draft.code = "123456"
        await gate.signIn.verifyCode()
        gate.signOut()
        #expect(!gate.isSignedIn)
        #expect(store.load() == nil)
        #expect(gate.signIn.step == .identity)
        #expect(gate.signIn.draft.code.isEmpty)
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `cd LifeOSKit && swift test --filter AccountGateTests`
Expected: a compile failure, "cannot find 'AccountGate' in scope".

- [ ] **Step 4: Implement**

```swift
// LifeOSKit/Sources/AccountUI/AccountGate.swift
import Foundation
import Observation
import Integrations

/// The signed-in session for an app that has one account at a time: restore
/// it on launch, keep it when sign-in succeeds, drop it on sign out.
///
/// `SignInModel` hands sessions over and never saves them, because LifeOS
/// files each account in its own Keychain slot. A companion app has one
/// slot, and this is what fills it.
@MainActor @Observable
public final class AccountGate {
    public private(set) var session: AuthSession?
    public private(set) var signIn: SignInModel

    private let backend: (any SignInBackend)?
    private let store: any AuthSessionStoring

    public init(backend: (any SignInBackend)?, store: any AuthSessionStoring) {
        self.backend = backend
        self.store = store
        self.session = store.load()
        // A placeholder so `self` is fully initialised before the real
        // model's closure captures it.
        self.signIn = SignInModel(backend: backend, store: store, onSignedIn: { _ in })
        self.signIn = makeSignIn()
    }

    public var isSignedIn: Bool { session != nil }

    /// Only a refusal from the server ends the session; being offline keeps
    /// it (see `SessionRefresher`).
    public func restore() async {
        guard let backend else { return }
        switch await backend.restore(store: store) {
        case .active(let refreshed):
            session = refreshed
        case .signedOut:
            session = nil
        case .rejected:
            signOut()
            signIn.report("Your session expired. Sign in again")
        }
    }

    public func signOut() {
        store.clear()
        session = nil
        signIn = makeSignIn()
    }

    private func makeSignIn() -> SignInModel {
        SignInModel(backend: backend, store: store) { [weak self] session in
            self?.keep(session)
        }
    }

    /// A session that cannot be stored is not a sign-in: the next launch
    /// would have nothing. Say so and stay on sign-in.
    private func keep(_ session: AuthSession) {
        do {
            try store.save(session)
            self.session = session
        } catch {
            signIn = makeSignIn()
            signIn.report("Couldn't save your sign-in on this device. Try again.")
        }
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `cd LifeOSKit && swift test --filter "AccountGateTests|SignInModelTests"`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/AccountUI/AccountGate.swift LifeOSKit/Tests/AccountUITests
git commit -m "feat(account): add AccountGate to keep one app's session"
```

### Task 2: The app's sources

**Files:**
- Create: `LifeOSFocus/LifeOSFocusApp.swift`, `LifeOSFocus/FocusConfig.swift`, `LifeOSFocus/FocusRootView.swift`, `LifeOSFocus/FocusHomeView.swift`, `LifeOSFocus/Info.plist`, `LifeOSFocus/LifeOSFocus.entitlements`

**Interfaces:**
- Consumes:
  - `AccountGate` (Task 1)
  - `IdentityScreen(model:totalSteps:onBack:)` and `CodeScreen(model:totalSteps:onBack:)`
  - `SharedSignIn.accessGroup`
  - `KeychainAuthSessionStore`
  - `EditorialMasthead`, `LifeOSTokens`, `LifeOSType`, `Space`, and `.editorial(...)` button styles from `DesignSystem`
- Produces: the source folder that Task 3's target compiles.

These files can't be compiled until Task 3 creates the target. The check for
this task is the Task 3 build. Write them exactly as below.

- [ ] **Step 1: Write the files**

```swift
// LifeOSFocus/LifeOSFocusApp.swift
import SwiftUI
import Integrations

@main
struct LifeOSFocusApp: App {
    init() {
        // The group LifeOS and its companion apps share for "Continue as".
        // Only an access token is ever left there; see `SharedSignIn`.
        SharedSignIn.accessGroup = "Z42YU5W6WY.com.shivvyas.lifeos.shared"
    }

    var body: some Scene {
        WindowGroup { FocusRootView() }
    }
}
```

```swift
// LifeOSFocus/FocusConfig.swift
import Foundation
import Integrations

/// What the Focus app reads from its Info.plist, which takes it from
/// `Config/Secrets.xcconfig`. A blank value (CI, a fresh clone) means no
/// backend, and sign-in says it is unavailable rather than failing silently.
enum FocusConfig {
    static var supabaseURL: URL? { string("SupabaseURL").flatMap(URL.init(string:)) }
    static var supabaseAnonKey: String? { string("SupabaseAnonKey") }

    static var auth: SupabaseAuth? {
        guard let url = supabaseURL, let key = supabaseAnonKey else { return nil }
        return SupabaseAuth(baseURL: url, anonKey: key)
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
```

```swift
// LifeOSFocus/FocusRootView.swift
import SwiftUI
import AccountUI
import Integrations

/// Sign-in until there is a session, then Home. The session is restored on
/// launch and on every return to the foreground, the same rule LifeOS uses.
struct FocusRootView: View {
    @State private var gate = AccountGate(backend: FocusConfig.auth, store: KeychainAuthSessionStore())
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if gate.isSignedIn {
                FocusHomeView(gate: gate)
            } else if gate.signIn.step == .code {
                CodeScreen(model: gate.signIn, totalSteps: 2, onBack: { _ = gate.signIn.back() })
            } else {
                IdentityScreen(model: gate.signIn, totalSteps: 2, onBack: { _ = gate.signIn.back() })
            }
        }
        .animation(.easeInOut(duration: 0.28), value: gate.isSignedIn)
        .task { await gate.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await gate.restore() } }
        }
    }
}
```

```swift
// LifeOSFocus/FocusHomeView.swift
import SwiftUI
import AccountUI
import DesignSystem

/// The starter Home. The moods, Resume last and recent sessions arrive with
/// the Focus code in the next slice; this proves the account end to end.
struct FocusHomeView: View {
    let gate: AccountGate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "LifeOS Focus", title: "Focus",
                                  detail: "Signed in as \(account).")
                Text("Your sessions will start here.")
                    .font(LifeOSType.body)
                    .foregroundStyle(Editorial.quietInk(scheme))
                Button("Sign out") { gate.signOut() }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }

    private var account: String {
        gate.session?.email ?? gate.session?.phone ?? "your account"
    }
}
```

Check the `EditorialMasthead` initializer labels before writing the call:
`grep -n "public init" LifeOSKit/Sources/DesignSystem/Editorial.swift`. If they
differ, use the real labels and ledger a ruling.

```xml
<!-- LifeOSFocus/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SupabaseAnonKey</key>
	<string>$(SUPABASE_ANON_KEY)</string>
	<key>SupabaseURL</key>
	<string>$(SUPABASE_URL)</string>
</dict>
</plist>
```

```xml
<!-- LifeOSFocus/LifeOSFocus.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- The app's own group first (the default for its own items), then the
	     group shared with LifeOS for the sign-in beacon. -->
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.shivvyas.lifeos.focus</string>
		<string>$(AppIdentifierPrefix)com.shivvyas.lifeos.shared</string>
	</array>
</dict>
</plist>
```

The Info.plist must be excluded from the synchronized group's build phases,
or Xcode copies it as a resource and the build fails with "Multiple commands
produce Info.plist". Task 3's script does this through the group's exception
set.

- [ ] **Step 2: Commit**

```bash
git add LifeOSFocus
git commit -m "feat(focus-app): add the app's sources: sign-in, starter Home, config"
```

### Task 3: Create the target

**Files:**
- Create: `scripts/add-focus-target.rb`
- Generated: `LIfeOS.xcodeproj/project.pbxproj`, `LIfeOS.xcodeproj/xcshareddata/xcschemes/LifeOSFocus.xcscheme`

**Interfaces:**
- Consumes: the `LifeOSFocus/` folder (Task 2), the local package reference
  to `LifeOSKit` already in the project, and the `Config/Secrets.xcconfig`
  file reference already in the project.
- Produces: target `LifeOSFocus` and scheme `LifeOSFocus`.

- [ ] **Step 1: Write the script**

```ruby
# scripts/add-focus-target.rb
# Adds the LifeOS Focus app target to LIfeOS.xcodeproj. Safe to re-run: it
# does nothing if the target already exists.
#   ruby scripts/add-focus-target.rb
require "xcodeproj"

PROJECT = File.expand_path("../LIfeOS.xcodeproj", __dir__)
NAME = "LifeOSFocus"
PRODUCTS = %w[AccountUI DesignSystem Integrations Persistence FocusSync]

project = Xcodeproj::Project.open(PROJECT)
if project.targets.any? { |t| t.name == NAME }
  puts "#{NAME} already exists"
  exit 0
end

target = project.new_target(:application, NAME, :ios, "26.0")

# Sources: one synchronized folder, like the LifeOS app, so new files need
# no project edits. Info.plist is excluded from its build phases.
group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
group.path = NAME
group.source_tree = "<group>"
exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
exceptions.target = target
exceptions.membership_exceptions = ["Info.plist"]
group.exceptions << exceptions
project.main_group.children << group
target.file_system_synchronized_groups << group

# Package products from the local LifeOSKit package.
package = project.root_object.package_references.find { |r| r.respond_to?(:relative_path) && r.relative_path.to_s.include?("LifeOSKit") } \
  or abort("no local LifeOSKit package reference")
PRODUCTS.each do |product|
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package
  dependency.product_name = product
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

secrets = project.files.find { |f| f.path == "Config/Secrets.xcconfig" } or abort("no Secrets.xcconfig reference")
target.build_configurations.each do |config|
  config.base_configuration_reference = secrets
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "com.shivvyas.lifeos.focus"
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["DEVELOPMENT_TEAM"] = "Z42YU5W6WY"
  s["CODE_SIGN_STYLE"] = "Automatic"
  s["CODE_SIGN_ENTITLEMENTS"] = "#{NAME}/#{NAME}.entitlements"
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["INFOPLIST_FILE"] = "#{NAME}/Info.plist"
  s["INFOPLIST_KEY_CFBundleDisplayName"] = "LifeOS Focus"
  s["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  s["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  s["INFOPLIST_KEY_UISupportedInterfaceOrientations"] = "UIInterfaceOrientationPortrait"
  s["INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad"] =
    "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "26.0"
  s["TARGETED_DEVICE_FAMILY"] = "1,2"
  s["SWIFT_VERSION"] = "6.0"
  s["MARKETING_VERSION"] = "1.0"
  s["CURRENT_PROJECT_VERSION"] = "1"
  s["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(PROJECT, NAME, true)
puts "added #{NAME}"
```

- [ ] **Step 2: Confirm the build fails before the script runs**

Run: `xcodebuild build -project LIfeOS.xcodeproj -scheme LifeOSFocus -destination 'generic/platform=iOS Simulator' -quiet`
Expected: "The project does not contain a scheme named LifeOSFocus" (or similar).

- [ ] **Step 3: Run the script, then build**

```bash
ruby scripts/add-focus-target.rb
xcodebuild build -project LIfeOS.xcodeproj -scheme LifeOSFocus \
  -destination 'generic/platform=iOS Simulator' -quiet > /tmp/focus-build.log 2>&1; echo exit=$?
grep error: /tmp/focus-build.log | sort -u | head
```

Expected: `exit=0`.

If the gem rejects a class or an attribute name, inspect what this gem
version supports with
`ruby -e 'require "xcodeproj"; p Xcodeproj::Project::Object.constants.grep(/Synchron/)'`.
Use the names it reports and ledger the ruling.

- [ ] **Step 4: Make sure LifeOS still builds, and that the script is safe to re-run**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' -quiet > /tmp/lifeos-build.log 2>&1; echo exit=$?
ruby scripts/add-focus-target.rb   # Expected: "LifeOSFocus already exists"
git diff --stat LIfeOS.xcodeproj   # Expected: no change from the re-run
```

- [ ] **Step 5: Check on the simulator**

Use the private simulator (`Affordance iPhone 17`,
`9CC475A6-7584-4C9A-9F04-FDA407427E73`):

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LifeOSFocus -destination 'id=9CC475A6-7584-4C9A-9F04-FDA407427E73' -derivedDataPath /tmp/focus-dd -quiet
xcrun simctl install 9CC475A6-7584-4C9A-9F04-FDA407427E73 /tmp/focus-dd/Build/Products/Debug-iphonesimulator/LifeOSFocus.app
xcrun simctl launch 9CC475A6-7584-4C9A-9F04-FDA407427E73 com.shivvyas.lifeos.focus
sleep 4; xcrun simctl io 9CC475A6-7584-4C9A-9F04-FDA407427E73 screenshot /tmp/focus-signin.png
```

Expected: the screenshot shows "Create your account" with the Email and
Phone channels, and the LifeOS header.

Then delete `/tmp/focus-dd`, because disk space is tight.

- [ ] **Step 6: Commit**

```bash
git add scripts/add-focus-target.rb LIfeOS.xcodeproj
git commit -m "feat(focus-app): add the LifeOS Focus target to the project"
```

### Task 4: Build it in CI

**Files:**
- Modify: `.github/workflows/ci.yml` (the build job)

- [ ] **Step 1: Add the step**

After the "Build for the simulator" step, add:

```yaml
      - name: Build LifeOS Focus for the simulator
        run: |
          set -o pipefail
          xcodebuild -project LIfeOS.xcodeproj -scheme LifeOSFocus \
            -destination 'generic/platform=iOS Simulator' \
            -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
            -skipPackagePluginValidation -quiet build 2>&1 | tee -a xcodebuild.log
```

- [ ] **Step 2: Check it locally the way CI runs it, with blank secrets**

```bash
cp Config/Secrets.xcconfig /tmp/secrets.bak && cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodebuild -project LIfeOS.xcodeproj -scheme LifeOSFocus -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet build > /tmp/ci-focus.log 2>&1; echo exit=$?
cp /tmp/secrets.bak Config/Secrets.xcconfig
zsh scripts/check-typography.sh | grep LifeOSFocus   # Expected: no lines
```

Expected: `exit=0`, and no typography findings in `LifeOSFocus/`.

- [ ] **Step 3: Commit, push and open the PR**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build the LifeOS Focus app"
git push -u origin feat/focus-app
```

Open a PR against `feat/focus-sync` (stacked), titled
"feat(focus-app): the LifeOS Focus app target". The body lists the owner
steps:
1. In the Apple Developer portal, register the App ID
   `com.shivvyas.lifeos.focus` with Keychain Sharing, or let automatic
   signing create it on the first device build.
2. Create the App Store Connect record "LifeOS Focus".
3. Choose an app icon.

Don't merge it.
