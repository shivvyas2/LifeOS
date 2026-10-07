import Testing
import Foundation
@testable import Integrations

@Suite struct GitHubOAuthTests {
    @Test func theAuthorizeURLAsksForRepoAndReadUserWithPKCE() throws {
        let session = GitHubOAuth.session(clientID: "abc", state: "s1", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let items = URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(session.url.absoluteString.hasPrefix("https://github.com/login/oauth/authorize?"))
        #expect(value("client_id") == "abc")
        #expect(value("redirect_uri") == "almanac://github-callback")
        #expect(value("scope") == "repo read:user")
        #expect(value("state") == "s1")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func theCodeComesBackWhenTheStateMatches() throws {
        let url = URL(string: "almanac://github-callback?code=xyz&state=s1")!
        #expect(try GitHubOAuth.code(from: url, expectedState: "s1") == "xyz")
        #expect(GitHubOAuth.state(in: url) == "s1")
    }

    @Test func aMismatchedStateIsRejected() {
        let url = URL(string: "almanac://github-callback?code=xyz&state=other")!
        #expect(throws: GitHubAuthError.stateMismatch) { try GitHubOAuth.code(from: url, expectedState: "s1") }
    }

    @Test func accessDeniedIsACancel() {
        let url = URL(string: "almanac://github-callback?error=access_denied&state=s1")!
        #expect(throws: GitHubAuthError.denied) { try GitHubOAuth.code(from: url, expectedState: "s1") }
    }

    @Test func theInMemoryStoreKeepsOneConnection() throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubConnection(token: "t", login: "me"))
        #expect(store.load()?.login == "me")
        store.clear()
        #expect(store.load() == nil)
    }
}
