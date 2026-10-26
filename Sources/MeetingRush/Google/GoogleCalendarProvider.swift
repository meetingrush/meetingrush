import AppKit
import MeetingRushCore
import Observation

/// Reads calendars from Google accounts through the Google Calendar API, signing in with the user's own OAuth client.
@MainActor
@Observable
final class GoogleCalendarProvider: CalendarProvider {
    static let sourceID = "google"
    let id = sourceID

    /// The OAuth client's ID, from a Google Cloud "Desktop app" client.
    var clientID: String {
        didSet {
            UserDefaults.standard.set(clientID, forKey: Keys.clientID)
            accessTokens = [:]
        }
    }

    /// Google doesn't treat a desktop client's secret as confidential, but it's kept in the keychain all the same.
    var clientSecret: String {
        get { secrets.clientSecret }
        set {
            secrets.clientSecret = newValue
            saveSecrets()
            accessTokens = [:]
        }
    }

    private(set) var accounts: [String]
    private(set) var isConnecting = false
    private(set) var connectError: String?
    private(set) var accountErrors: [String: String] = [:]

    private var secrets: Secrets
    @ObservationIgnored private var accessTokens: [String: AccessToken] = [:]
    @ObservationIgnored private var calendarCache: [String: Cached<[CalendarInfo]>] = [:]
    @ObservationIgnored private var eventCache: [CalendarInfo.ID: Cached<[Meeting]>] = [:]
    @ObservationIgnored private var googleCalendarIDs: [CalendarInfo.ID: (account: String, calendarID: String)] = [:]
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var onChange: (@MainActor () -> Void)?

    private static let calendarListLifetime: TimeInterval = 15 * 60
    private static let eventsLifetime: TimeInterval = 5 * 60
    private static let signInTimeout: Duration = .seconds(5 * 60)

    init() {
        let clientID = UserDefaults.standard.string(forKey: Keys.clientID) ?? ""
        let accounts = UserDefaults.standard.stringArray(forKey: Keys.accounts) ?? []
        self.clientID = clientID
        self.accounts = accounts
        // Reading the keychain can prompt after an ad-hoc rebuild, so it's skipped for users who never set up Google.
        secrets = accounts.isEmpty && clientID.isEmpty ? Secrets() : Secrets.load()
    }

    var canConnect: Bool {
        !clientID.trimmed.isEmpty && !clientSecret.trimmed.isEmpty && !isConnecting
    }

    // MARK: CalendarProvider

    func requestAccess() async throws -> Bool {
        !accounts.isEmpty
    }

    func calendars() async throws -> [CalendarInfo] {
        var result: [CalendarInfo] = []
        for account in accounts {
            if let cached = calendarCache[account], cached.isFresh(Self.calendarListLifetime) {
                result += cached.value
                continue
            }
            do {
                var entries: [GoogleCalendarAPI.CalendarListEntry] = []
                var pageToken: String?
                repeat {
                    let page: GoogleCalendarAPI.CalendarList = try await get(GoogleCalendarAPI.calendarListURL(pageToken: pageToken), account: account)
                    entries += page.items ?? []
                    pageToken = page.nextPageToken
                } while pageToken != nil

                let calendars = entries.map { entry in
                    let info = CalendarInfo(
                        id: "google:\(account):\(entry.id)",
                        title: entry.summaryOverride ?? entry.summary ?? entry.id,
                        account: account,
                        color: entry.backgroundColor.flatMap(CalendarInfo.Color.init(hex:)),
                        source: id,
                        enabledByDefault: entry.primary == true || entry.selected == true
                    )
                    googleCalendarIDs[info.id] = (account, entry.id)
                    return info
                }
                calendarCache[account] = Cached(value: calendars)
                accountErrors[account] = nil
                result += calendars
            } catch {
                // A failed refresh keeps the last list, so a network blip doesn't silence alerts.
                accountErrors[account] = error.localizedDescription
                result += calendarCache[account]?.value ?? []
            }
        }
        return result
    }

    func meetings(from start: Date, to end: Date, in calendars: [CalendarInfo]) async throws -> [Meeting] {
        var result: [Meeting] = []
        for calendar in calendars {
            if let cached = eventCache[calendar.id], cached.isFresh(Self.eventsLifetime) {
                result += cached.value
                continue
            }
            guard let (account, calendarID) = googleCalendarIDs[calendar.id] else { continue }
            do {
                var meetings: [Meeting] = []
                var pageToken: String?
                repeat {
                    let url = GoogleCalendarAPI.eventsURL(calendarID: calendarID, from: start, to: end, pageToken: pageToken)
                    let page: GoogleCalendarAPI.Events = try await get(url, account: account)
                    meetings += (page.items ?? []).compactMap { $0.meeting(in: calendar) }
                    pageToken = page.nextPageToken
                } while pageToken != nil
                eventCache[calendar.id] = Cached(value: meetings)
                result += meetings
            } catch {
                accountErrors[account] = error.localizedDescription
                result += eventCache[calendar.id]?.value ?? []
            }
        }
        return result
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        onChange = handler
    }

    // MARK: Accounts

    /// Opens Google's sign-in page in the browser and adds the account once the user approves.
    func connect() {
        guard canConnect else { return }
        connectError = nil
        isConnecting = true
        connectTask = Task { [weak self] in
            await self?.signIn()
            self?.isConnecting = false
            self?.connectTask = nil
        }
    }

    func cancelConnect() {
        connectTask?.cancel()
    }

    func remove(_ account: String) {
        if let refreshToken = secrets.refreshTokens.removeValue(forKey: account) {
            saveSecrets()
            revoke(refreshToken)
        }
        accounts.removeAll { $0 == account }
        UserDefaults.standard.set(accounts, forKey: Keys.accounts)
        accessTokens[account] = nil
        accountErrors[account] = nil
        calendarCache[account] = nil
        googleCalendarIDs = googleCalendarIDs.filter { $0.value.account != account }
        onChange?()
    }

    private func signIn() async {
        do {
            let server = try LoopbackServer()
            let port = try await server.start()
            defer { server.stop() }
            let timeout = Task {
                try await Task.sleep(for: Self.signInTimeout)
                server.stop()
            }
            defer { timeout.cancel() }

            let pkce = GoogleOAuth.PKCE.generate()
            let state = GoogleOAuth.randomToken()
            let redirectURI = "http://127.0.0.1:\(port)"
            NSWorkspace.shared.open(GoogleOAuth.authorizationURL(clientID: clientID.trimmed, redirectURI: redirectURI, pkce: pkce, state: state))

            let target = try await withTaskCancellationHandler {
                try await server.waitForCallback()
            } onCancel: {
                server.stop()
            }
            switch GoogleOAuth.parseCallback(target, expectedState: state) {
            case .code(let code):
                let tokens = try await requestToken([
                    "code": code,
                    "grant_type": "authorization_code",
                    "redirect_uri": redirectURI,
                    "code_verifier": pkce.verifier,
                ])
                guard let refreshToken = tokens.refreshToken, let email = tokens.idToken.flatMap(GoogleOAuth.email(fromIDToken:)) else {
                    throw GoogleError.signInFailed("Google didn't return the account's details.")
                }
                add(account: email, refreshToken: refreshToken, accessToken: tokens)
            case .failure(let reason):
                throw GoogleError.signInFailed(reason == "access_denied" ? "Access wasn't granted." : reason)
            case nil:
                throw GoogleError.signInFailed("Google's response had no result.")
            }
        } catch is CancellationError {
            return
        } catch {
            connectError = error.localizedDescription
        }
    }

    private func add(account: String, refreshToken: String, accessToken tokens: GoogleOAuth.TokenResponse) {
        secrets.refreshTokens[account] = refreshToken
        saveSecrets()
        accessTokens[account] = AccessToken(value: tokens.accessToken, expiry: .now + tokens.expiresIn)
        if !accounts.contains(account) {
            accounts.append(account)
            UserDefaults.standard.set(accounts, forKey: Keys.accounts)
        }
        accountErrors[account] = nil
        calendarCache[account] = nil
        NSApp.activate()
        onChange?()
    }

    // MARK: Requests

    private func get<T: Decodable>(_ url: URL, account: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken(for: account))", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { accessTokens[account] = nil }
            throw GoogleError.requestFailed(status, Self.apiErrorMessage(data))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func accessToken(for account: String) async throws -> String {
        if let token = accessTokens[account], token.expiry > .now + 60 {
            return token.value
        }
        guard let refreshToken = secrets.refreshTokens[account] else { throw GoogleError.signInExpired }
        let tokens = try await requestToken(["refresh_token": refreshToken, "grant_type": "refresh_token"])
        accessTokens[account] = AccessToken(value: tokens.accessToken, expiry: .now + tokens.expiresIn)
        return tokens.accessToken
    }

    private func requestToken(_ parameters: [String: String]) async throws -> GoogleOAuth.TokenResponse {
        var request = URLRequest(url: GoogleOAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parameters = parameters
        parameters["client_id"] = clientID.trimmed
        parameters["client_secret"] = clientSecret.trimmed
        request.httpBody = GoogleOAuth.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            return try JSONDecoder().decode(GoogleOAuth.TokenResponse.self, from: data)
        }
        let error = try? JSONDecoder().decode(GoogleOAuth.ErrorResponse.self, from: data)
        if error?.error == "invalid_grant" {
            throw GoogleError.signInExpired
        }
        throw GoogleError.signInFailed(error?.errorDescription ?? error?.error ?? "Google rejected the sign-in.")
    }

    private func revoke(_ token: String) {
        var request = URLRequest(url: GoogleOAuth.revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleOAuth.formBody(["token": token])
        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    /// The `error.message` of a Google API error body, which explains problems such as the Calendar API being disabled.
    private static func apiErrorMessage(_ data: Data) -> String? {
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (body?["error"] as? [String: Any])?["message"] as? String
    }

    private func saveSecrets() {
        guard let data = try? JSONEncoder().encode(secrets) else { return }
        Keychain.write(data, service: Secrets.service, account: Secrets.account)
    }

    private enum Keys {
        static let clientID = "googleClientID"
        static let accounts = "googleAccounts"
    }
}

private struct Secrets: Codable {
    var clientSecret = ""
    /// Keyed by account email.
    var refreshTokens: [String: String] = [:]

    // One item for everything, so a rebuild with a new ad-hoc signature prompts for keychain access only once.
    static let service = "\(Bundle.main.bundleIdentifier ?? "MeetingRush").google"
    static let account = "secrets"

    static func load() -> Secrets {
        Keychain.read(service: service, account: account).flatMap { try? JSONDecoder().decode(Secrets.self, from: $0) } ?? Secrets()
    }
}

private struct AccessToken {
    let value: String
    let expiry: Date
}

private struct Cached<Value> {
    let value: Value
    var fetchedAt = Date.now

    func isFresh(_ lifetime: TimeInterval) -> Bool {
        Date.now.timeIntervalSince(fetchedAt) < lifetime
    }
}

enum GoogleError: LocalizedError {
    case signInFailed(String)
    case signInExpired
    case requestFailed(Int, String?)

    var errorDescription: String? {
        switch self {
        case .signInFailed(let reason): "Sign-in failed: \(reason)"
        case .signInExpired: "Google sign-in expired. Remove the account and connect it again."
        case .requestFailed(let status, let message): message ?? "Google returned HTTP \(status)."
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
