import Foundation
import Testing
@testable import MeetingRushCore

struct GoogleOAuthTests {
    @Test func derivesTheS256Challenge() {
        // Expected value computed independently with `openssl dgst -sha256 -binary | base64` and URL-safe characters.
        let pkce = GoogleOAuth.PKCE(verifier: "dBjftJeZ4CVP-mJ92K9qbVFsObkRxRaEDvBZQxBhfbo")
        #expect(pkce.challenge == "PvzucvxJQe-LrRJFoSbGFZasaoQkVQcJAfD4PIpEXI4")
    }

    @Test func generatesUrlSafeRandomTokens() {
        let token = GoogleOAuth.randomToken()
        #expect(token.count == 43)
        #expect(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(token != GoogleOAuth.randomToken())
    }

    @Test func buildsTheAuthorizationURL() throws {
        let pkce = GoogleOAuth.PKCE(verifier: "verifier")
        let url = GoogleOAuth.authorizationURL(clientID: "id.apps.googleusercontent.com", redirectURI: "http://127.0.0.1:5000", pkce: pkce, state: "s")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "accounts.google.com")
        #expect(query["client_id"] == "id.apps.googleusercontent.com")
        #expect(query["redirect_uri"] == "http://127.0.0.1:5000")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["scope"] == "https://www.googleapis.com/auth/calendar.readonly openid email")
        #expect(query["access_type"] == "offline")
    }

    @Test func parsesTheRedirect() {
        #expect(GoogleOAuth.parseCallback("/?state=s&code=4%2Fabc&scope=x", expectedState: "s") == .code("4/abc"))
        #expect(GoogleOAuth.parseCallback("/?error=access_denied&state=s", expectedState: "s") == .failure("access_denied"))
        #expect(GoogleOAuth.parseCallback("/?state=other&code=abc", expectedState: "s") == .failure("The sign-in response didn't match the request."))
        #expect(GoogleOAuth.parseCallback("/favicon.ico", expectedState: "s") == nil)
    }

    @Test func readsTheEmailFromAnIDToken() {
        let payload = Data(#"{"email":"me@example.com","sub":"1"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(GoogleOAuth.email(fromIDToken: "header.\(payload).signature") == "me@example.com")
        #expect(GoogleOAuth.email(fromIDToken: "garbage") == nil)
    }

    @Test func encodesFormBodies() {
        let body = GoogleOAuth.formBody(["code": "4/abc", "grant_type": "authorization_code"])
        #expect(String(decoding: body, as: UTF8.self) == "code=4%2Fabc&grant_type=authorization_code")
    }
}
