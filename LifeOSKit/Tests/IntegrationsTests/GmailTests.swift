import Testing
import Foundation
@testable import Integrations

@Suite struct GoogleOAuthTests {
    @Test func theAuthorizeURLAsksForGmailReadOnlyWithPKCE() {
        let session = GoogleOAuth.session(clientID: "123-abc.apps.googleusercontent.com",
                                          state: "s1", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let items = URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(session.url.absoluteString.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
        #expect(value("scope") == "openid email https://www.googleapis.com/auth/gmail.readonly")
        #expect(value("redirect_uri") == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(value("access_type") == "offline")
        #expect(value("prompt") == "consent")
        #expect(value("response_type") == "code")
    }

    @Test func theReversedClientID() {
        #expect(GoogleOAuth.reversed(clientID: "123-abc.apps.googleusercontent.com") == "com.googleusercontent.apps.123-abc")
    }

    @Test func theCallback() throws {
        #expect(try GoogleOAuth.code(from: URL(string: "com.googleusercontent.apps.1:/oauth2redirect?state=s&code=c")!, expectedState: "s") == "c")
        #expect(throws: GoogleAuthError.stateMismatch) {
            try GoogleOAuth.code(from: URL(string: "x:/r?state=other&code=c")!, expectedState: "s")
        }
        #expect(throws: GoogleAuthError.denied) {
            try GoogleOAuth.code(from: URL(string: "x:/r?state=s&error=access_denied")!, expectedState: "s")
        }
    }

    @Test func tokensAndTheEmail() throws {
        let payload = Data(#"{"email":"me@gmail.com"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let json = #"{"access_token":"a","refresh_token":"r","expires_in":3599,"id_token":"h.\#(payload).s"}"#
        let response = try JSONDecoder().decode(GoogleTokenResponse.self, from: Data(json.utf8))
        #expect(response.accessToken == "a" && response.refreshToken == "r" && response.expiresIn == 3599)
        #expect(GoogleOAuth.email(fromIDToken: response.idToken ?? "") == "me@gmail.com")
    }

    @Test func expiryAndRefusal() {
        let now = Date(timeIntervalSince1970: 1_000)
        let soon = GoogleConnection(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(30), email: "e")
        let later = GoogleConnection(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(600), email: "e")
        #expect(soon.needsRefresh(now: now))
        #expect(!later.needsRefresh(now: now))
        #expect(GoogleOAuth.refreshOutcome(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)) == .reconnect)
        #expect(GoogleOAuth.refreshOutcome(status: 503, body: Data()) == .unavailable)
    }

    @Test func formBodies() {
        let body = String(data: GoogleOAuth.tokenRequestBody(code: "c", verifier: "v", clientID: "id", redirectURI: "x:/r"), encoding: .utf8)!
        #expect(body.contains("grant_type=authorization_code") && body.contains("code_verifier=v") && body.contains("client_id=id"))
        #expect(!body.contains("client_secret"))
        let refresh = String(data: GoogleOAuth.refreshRequestBody(refreshToken: "r", clientID: "id"), encoding: .utf8)!
        #expect(refresh.contains("grant_type=refresh_token") && refresh.contains("refresh_token=r"))
    }
}

@Suite struct GmailAPITests {
    private func message(from: String, unread: Bool = true, snippet: String = "Sign by Friday") -> Data {
        let labels = unread ? #"["INBOX","IMPORTANT","UNREAD"]"# : #"["INBOX","IMPORTANT"]"#
        return Data(#"""
        {"id":"m1","threadId":"t1","labelIds":\#(labels),"snippet":"\#(snippet)","internalDate":"1760000000000",
         "payload":{"headers":[{"name":"from","value":"\#(from.replacingOccurrences(of: "\"", with: "\\\""))"},{"name":"Subject","value":"Contract review"}]}}
        """#.utf8)
    }

    @Test func theQuery() {
        let items = URLComponents(url: GmailAPI.listURL(), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "q" }?.value == "in:inbox category:primary is:important newer_than:2d")
        #expect(items.first { $0.name == "maxResults" }?.value == "25")
        let meta = GmailAPI.messageURL(id: "m1").absoluteString
        #expect(meta.contains("/messages/m1") && meta.contains("format=metadata") && meta.contains("metadataHeaders=From"))
    }

    @Test func listAndMessage() throws {
        #expect(GmailAPI.messageIDs(from: Data(#"{"messages":[{"id":"a","threadId":"x"},{"id":"b","threadId":"y"}]}"#.utf8)) == ["a", "b"])
        #expect(GmailAPI.messageIDs(from: Data(#"{"resultSizeEstimate":0}"#.utf8)).isEmpty)
        let item = try #require(GmailAPI.item(from: message(from: #""Priya Shah" <priya@example.com>"#)))
        #expect(item.sender == "Priya Shah" && item.senderEmail == "priya@example.com")
        #expect(item.subject == "Contract review" && item.threadId == "t1" && item.isUnread)
        #expect(item.receivedAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(GmailAPI.item(from: message(from: "x@y.com", unread: false))?.isUnread == false)
    }

    @Test func senders() {
        #expect(GmailAPI.sender(from: #""Priya Shah" <priya@example.com>"#).name == "Priya Shah")
        #expect(GmailAPI.sender(from: "Priya <p@x.com>").name == "Priya")
        #expect(GmailAPI.sender(from: "p@x.com").name == "p@x.com")
        #expect(GmailAPI.sender(from: "=?UTF-8?B?Sm9zw6k=?= <j@x.com>").name == "José")
        #expect(GmailAPI.sender(from: "=?UTF-8?Q?Jos=C3=A9_P?= <j@x.com>").name == "José P")
    }
}

@Suite struct MailDigestTests {
    @Test func countLine() {
        #expect(MailDigest.countLine(0) == "Nothing needs you")
        #expect(MailDigest.countLine(1) == "1 needs you")
        #expect(MailDigest.countLine(4) == "4 need you")
    }

    private func item(_ id: String, _ seconds: Double) -> MailItem {
        MailItem(id: id, threadId: id, sender: id, senderEmail: "\(id)@x", subject: "S", snippet: "s",
                 receivedAt: Date(timeIntervalSince1970: seconds), isUnread: true)
    }

    @Test func capAndOrder() {
        let items = (0..<7).map { item("m\($0)", Double($0)) }
        var verdicts: [String: MailVerdict] = [:]
        for n in 0..<3 { verdicts["m\(n)"] = MailVerdict(bucket: .needsYou, summary: "do \(n)") }
        for n in 3..<7 { verdicts["m\(n)"] = MailVerdict(bucket: .fyi, summary: "fyi \(n)") }
        let digest = MailDigest.make(items: items, verdicts: verdicts)
        #expect(digest.needsYou.map(\.item.id) == ["m2", "m1", "m0"])
        #expect(digest.fyi.map(\.item.id) == ["m6", "m5"])
        #expect(digest.needsYouCount == 3)

        let urgent = (0..<6).map { item("u\($0)", Double($0)) }
        let all = Dictionary(uniqueKeysWithValues: urgent.map { ($0.id, MailVerdict(bucket: .needsYou, summary: "x")) })
        let full = MailDigest.make(items: urgent, verdicts: all)
        #expect(full.needsYou.count == 5 && full.fyi.isEmpty && full.needsYouCount == 6)
    }
}

@Suite struct MailFallbackTests {
    @Test func entities() {
        let item = MailItem(id: "m", threadId: "t", sender: "A", senderEmail: "a@x", subject: "S",
                            snippet: "It&#39;s fine &amp; done &quot;now&quot;", receivedAt: .now, isUnread: false)
        let verdict = MailFallback.verdict(for: item)
        #expect(verdict.bucket == .fyi)
        #expect(verdict.summary == "It's fine & done \"now\"")
    }

    @Test func longSnippetsAreCutOnAWord() {
        let text = String(repeating: "word ", count: 40)
        let item = MailItem(id: "m", threadId: "t", sender: "A", senderEmail: "a@x", subject: "S",
                            snippet: text, receivedAt: .now, isUnread: false)
        let summary = MailFallback.verdict(for: item).summary
        #expect(summary.count <= 90)
        #expect(summary.hasSuffix("…"))
        #expect(!summary.dropLast().hasSuffix(" "))
    }
}

@Suite struct MailVerdictCacheTests {
    @Test func remembersAndCaps() {
        let cache = MailVerdictCache(defaults: UserDefaults(suiteName: "verdicts.\(UUID().uuidString)")!)
        cache.store(MailVerdict(bucket: .needsYou, summary: "x"), for: "first")
        #expect(cache.verdict(for: "first")?.bucket == .needsYou)
        for n in 0..<205 { cache.store(MailVerdict(bucket: .fyi, summary: "\(n)"), for: "m\(n)") }
        #expect(cache.verdict(for: "first") == nil)
        #expect(cache.verdict(for: "m204") != nil)
        #expect(cache.count == 200)
    }
}
