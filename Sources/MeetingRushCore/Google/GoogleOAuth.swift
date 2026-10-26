import CryptoKit
import Foundation

/// Google's OAuth 2.0 flow for desktop apps: the browser signs in and redirects to a loopback address.
public enum GoogleOAuth {
    public static let scopes = ["https://www.googleapis.com/auth/calendar.readonly", "openid", "email"]
    public static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// A Proof Key for Code Exchange pair (RFC 7636): the challenge goes in the sign-in URL, the verifier in the token request.
    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String

        public init(verifier: String) {
            self.verifier = verifier
            challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        }

        public static func generate() -> PKCE {
            PKCE(verifier: randomToken())
        }
    }

    /// A URL-safe random string with 256 bits of entropy.
    public static func randomToken() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64URLEncoded
    }

    public static func authorizationURL(clientID: String, redirectURI: String, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Offline access plus a forced consent screen is what makes Google return a refresh token every time.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    public enum Callback: Equatable, Sendable {
        case code(String)
        case failure(String)
    }

    /// Reads the redirect's request target, such as `/?state=…&code=…`.
    ///
    /// Returns nil when the target carries neither a code nor an error, such as a browser's favicon request.
    public static func parseCallback(_ requestTarget: String, expectedState: String) -> Callback? {
        guard let items = URLComponents(string: requestTarget)?.queryItems else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") {
            return .failure(error)
        }
        guard let code = value("code") else { return nil }
        guard value("state") == expectedState else {
            return .failure("The sign-in response didn't match the request.")
        }
        return .code(code)
    }

    public struct TokenResponse: Decodable, Sendable {
        public let accessToken: String
        public let expiresIn: TimeInterval
        public let refreshToken: String?
        public let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    public struct ErrorResponse: Decodable, Sendable {
        public let error: String
        public let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    /// The `email` claim of an ID token.
    ///
    /// The signature isn't checked: the token comes straight from Google's token endpoint over TLS.
    public static func email(fromIDToken idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = segments[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return claims["email"] as? String
    }

    /// Encodes `parameters` as an `application/x-www-form-urlencoded` body.
    public static func formBody(_ parameters: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
