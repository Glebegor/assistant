import Foundation

/// Signing in with your GitHub Copilot subscription, so Copilot offers the same models as in
/// VS Code (Claude, the newest GPT…). This is the API the Copilot editor plugins use; GitHub
/// doesn't document it for other apps, so it may change. Without it Copilot uses GitHub Models.
///
/// The GitHub sign-in (device code) is kept in the Keychain; it's exchanged for a short-lived
/// Copilot token that is kept in memory only.
enum CopilotAuth {
    static let oauthAccount = "copilot-oauth-token"
    /// The client id of the Copilot editor plugins.
    private static let clientID = "Iv1.b507a08c87ecfe98"
    static let defaultAPI = URL(string: "https://api.githubcopilot.com")!

    static var isSignedIn: Bool { Keychain.read(oauthAccount) != nil }

    /// Headers the Copilot API expects from an editor.
    static let editorHeaders = [
        "Editor-Version": "vscode/1.99.0",
        "Editor-Plugin-Version": "copilot-chat/0.26.0",
        "User-Agent": "GitHubCopilotChat/0.26.0",
        "Copilot-Integration-Id": "vscode-chat",
    ]

    // MARK: Device sign-in

    struct DeviceCode: Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let interval: Int
        let expires: Date
    }

    static func startSignIn() async throws -> DeviceCode {
        let json = try await post("https://github.com/login/device/code", ["client_id": clientID, "scope": "read:user"])
        guard let device = json["device_code"]?.string, let user = json["user_code"]?.string else {
            throw ChatError(message: L("GitHub didn't start the sign-in. Try again."))
        }
        return DeviceCode(deviceCode: device, userCode: user,
                          verificationURL: URL(string: json["verification_uri"]?.string ?? "https://github.com/login/device")!,
                          interval: json["interval"]?.int ?? 5,
                          expires: Date().addingTimeInterval(TimeInterval(json["expires_in"]?.int ?? 900)))
    }

    /// Waits until you enter the code on github.com, then checks the account has Copilot.
    static func finishSignIn(_ code: DeviceCode) async throws {
        var interval = code.interval
        while Date() < code.expires {
            try await Task.sleep(for: .seconds(interval))
            let json = try await post("https://github.com/login/oauth/access_token",
                                      ["client_id": clientID, "device_code": code.deviceCode,
                                       "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            if let token = json["access_token"]?.string {
                // Fails here (and nothing is saved) when the account has no Copilot.
                _ = try await CopilotTokens.shared.fetch(oauth: token)
                Keychain.save(token, for: oauthAccount)
                return
            }
            switch json["error"]?.string {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw ChatError(message: L("The sign-in was cancelled on GitHub."))
            default: throw ChatError(message: json["error_description"]?.string ?? L("The GitHub sign-in failed."))
            }
        }
        throw ChatError(message: L("The code expired. Sign in again."))
    }

    static func signOut() {
        Keychain.delete(oauthAccount)
        Task { await CopilotTokens.shared.clear() }
    }

    /// A request to the Copilot API, with a fresh Copilot token and the editor headers.
    static func request(path: String, oauth: String) async throws -> URLRequest {
        let session = try await CopilotTokens.shared.token(oauth: oauth)
        var request = URLRequest(url: session.api.appending(path: path))
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        for (field, value) in editorHeaders { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }

    /// Copilot asks you to turn some models on (Claude, previews) before using them, as VS Code
    /// does the first time you pick one.
    static func enableModel(_ model: String, oauth: String) async {
        guard await CopilotTokens.shared.firstUse(of: model), var request = try? await request(path: "models/\(model)/policy", oauth: oauth) else { return }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONValue.object(["state": "enabled"]).encoded()
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func post(_ url: String, _ form: [String: String]) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONValue.object(form.mapValues { .string($0) }).encoded()
        let (data, _) = try await URLSession.shared.data(for: request)
        return JSONValue.parse(data) ?? .null
    }
}

/// The short-lived Copilot token (about 30 minutes), renewed before it runs out.
actor CopilotTokens {
    static let shared = CopilotTokens()

    struct Session: Sendable {
        let token: String
        let api: URL
        let expires: Date
    }

    private var session: Session?
    private var sessionOAuth: String?

    func token(oauth: String) async throws -> Session {
        if let session, sessionOAuth == oauth, session.expires.timeIntervalSinceNow > 120 { return session }
        return try await fetch(oauth: oauth)
    }

    func fetch(oauth: String) async throws -> Session {
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!, timeoutInterval: 30)
        request.setValue("token \(oauth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in CopilotAuth.editorHeaders { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = JSONValue.parse(data) ?? .null
        guard (response as? HTTPURLResponse)?.statusCode == 200, let token = json["token"]?.string else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ChatError(message: status == 401
                ? L("GitHub signed you out of Copilot. Sign in again in Settings → Assistant.")
                : L("This GitHub account has no Copilot subscription (or Copilot is turned off for it)."))
        }
        let api = json["endpoints"]?["api"]?.string.flatMap(URL.init(string:)) ?? CopilotAuth.defaultAPI
        let expires = Date(timeIntervalSince1970: TimeInterval(json["expires_at"]?.int ?? Int(Date().timeIntervalSince1970) + 1500))
        let session = Session(token: token, api: api, expires: expires)
        self.session = session
        sessionOAuth = oauth
        return session
    }

    private var usedModels: Set<String> = []

    /// True the first time a model is used in this session.
    func firstUse(of model: String) -> Bool { usedModels.insert(model).inserted }

    func clear() {
        session = nil
        sessionOAuth = nil
    }
}
