import AppKit
import CryptoKit
import Foundation
import Network

/// Signing in to Google with your own OAuth client (Google Cloud → Credentials → Desktop app).
/// The browser shows Google's sign-in; Google sends the result back to a tiny local web server on
/// 127.0.0.1, and the refresh token is kept in the Keychain. Data goes only between your Mac and Google.
enum GoogleAuth {
    static let clientIDKey = "google.clientID"
    static let emailKey = "google.email"
    static let secretAccount = "google-client-secret"
    static let refreshAccount = "google-refresh-token"
    static let consoleURL = URL(string: "https://console.cloud.google.com/apis/credentials")!
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/drive",
        calendarScope,
    ]
    static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
    private static let grantedScopesKey = "google.grantedScopes"

    /// Signed in before the calendar was added, or the calendar box was unticked on Google's page.
    static var hasCalendarAccess: Bool {
        isConnected && (UserDefaults.standard.string(forKey: grantedScopesKey) ?? "").contains(calendarScope)
    }

    /// Signs in again with the saved client (e.g. to add calendar access).
    @MainActor
    static func signInAgain() async throws {
        guard let clientID, let secret = Keychain.read(secretAccount) else {
            throw ChatError(message: L("Google isn't connected. Sign in in Settings → Services."))
        }
        try await signIn(clientID: clientID, secret: secret)
    }

    static var clientID: String? { UserDefaults.standard.string(forKey: clientIDKey).flatMap { $0.isEmpty ? nil : $0 } }
    static var email: String? { UserDefaults.standard.string(forKey: emailKey) }
    static var isConnected: Bool { Keychain.read(refreshAccount) != nil }

    private static let tokens = TokenCache()

    /// A valid access token, refreshed when it has expired.
    static func accessToken() async throws -> String {
        if let token = await tokens.valid() { return token }
        guard let clientID, let secret = Keychain.read(secretAccount), let refresh = Keychain.read(refreshAccount) else {
            throw ChatError(message: L("Google isn't connected. Sign in in Settings → Services."))
        }
        let response = try await tokenRequest([
            "client_id": clientID, "client_secret": secret, "refresh_token": refresh, "grant_type": "refresh_token",
        ])
        guard let token = response["access_token"]?.string else {
            throw ChatError(message: L("Google sign-in expired. Sign in again in Settings → Services."))
        }
        await tokens.store(token, lifetime: TimeInterval(response["expires_in"]?.int ?? 3600))
        return token
    }

    /// Opens Google's sign-in in the browser and waits until you finish it there.
    @MainActor
    static func signIn(clientID: String, secret: String) async throws {
        let verifier = Data((0..<48).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = UUID().uuidString

        let receiver = try await LoopbackReceiver.start()
        defer { receiver.stop() }
        let redirect = "http://127.0.0.1:\(receiver.port)"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        NSWorkspace.shared.open(components.url!)

        let query = try await receiver.waitForQuery(timeout: 300)
        guard query["state"] == state else { throw ChatError(message: L("Google sign-in failed. Try again.")) }
        if let error = query["error"] { throw ChatError(message: L("Google sign-in was cancelled (%@).", error)) }
        guard let code = query["code"] else { throw ChatError(message: L("Google sign-in failed. Try again.")) }

        let response = try await tokenRequest([
            "client_id": clientID, "client_secret": secret, "code": code, "code_verifier": verifier,
            "redirect_uri": redirect, "grant_type": "authorization_code",
        ])
        guard let refresh = response["refresh_token"]?.string, let access = response["access_token"]?.string else {
            throw ChatError(message: response["error_description"]?.string ?? L("Google sign-in failed. Try again."))
        }
        UserDefaults.standard.set(clientID, forKey: clientIDKey)
        UserDefaults.standard.set(response["scope"]?.string ?? "", forKey: grantedScopesKey)
        Keychain.save(secret, for: secretAccount)
        Keychain.save(refresh, for: refreshAccount)
        await tokens.store(access, lifetime: TimeInterval(response["expires_in"]?.int ?? 3600))

        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: request), let address = JSONValue.parse(data)?["emailAddress"]?.string {
            UserDefaults.standard.set(address, forKey: emailKey)
        }
    }

    static func signOut() async {
        Keychain.delete(refreshAccount)
        UserDefaults.standard.removeObject(forKey: emailKey)
        await tokens.clear()
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return JSONValue.parse(data) ?? .null
    }

    private actor TokenCache {
        private var token: String?
        private var expires = Date.distantPast

        func valid() -> String? { Date() < expires ? token : nil }
        func store(_ token: String, lifetime: TimeInterval) {
            self.token = token
            expires = Date().addingTimeInterval(lifetime - 120)
        }
        func clear() { token = nil; expires = .distantPast }
    }
}

/// Waits for the browser to come back to http://127.0.0.1:<port>/?code=… after signing in.
final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "RightHand.GoogleSignIn")
    private var continuation: CheckedContinuation<[String: String], Error>?
    /// The answer, if the browser came back before anyone waited for it.
    private var pending: [String: String]?
    private(set) var port: UInt16 = 0

    private init(listener: NWListener) { self.listener = listener }

    static func start() async throws -> LoopbackReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let receiver = LoopbackReceiver(listener: try NWListener(using: parameters))
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            // Runs on the receiver's serial queue, so this flag needs no lock.
            nonisolated(unsafe) var resumed = false
            receiver.listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    receiver.port = receiver.listener.port?.rawValue ?? 0
                    ready.resume()
                case .failed(let error):
                    resumed = true
                    ready.resume(throwing: error)
                default: break
                }
            }
            receiver.listener.newConnectionHandler = { [weak receiver] in receiver?.handle($0) }
            receiver.listener.start(queue: receiver.queue)
        }
        return receiver
    }

    func waitForQuery(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let pending = self.pending { return continuation.resume(returning: pending) }
                self.continuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(ChatError(message: L("Google sign-in timed out. Try again."))))
                }
            }
        }
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            // "GET /?code=…&state=… HTTP/1.1"
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let items = URLComponents(string: "http://127.0.0.1" + target)?.queryItems ?? []
            let query = Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { $1 })
            let isResult = query["code"] != nil || query["error"] != nil
            let page = isResult ? L("RightHand is connected. You can close this tab.") : ""
            let html = "<html><body style=\"font: 16px -apple-system; text-align: center; padding-top: 80px\">\(page)</body></html>"
            let response = "HTTP/1.1 \(isResult ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if isResult { self.finish(.success(query)) }
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard let continuation else {
            if case .success(let query) = result { pending = query }
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
