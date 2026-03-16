import Foundation
import AppKit
import Network
import Security

final class SlackManager: ObservableObject {
    static let shared = SlackManager()

    @Published var isAuthenticated = false
    @Published private(set) var pausedUntil: Date?

    var isPaused: Bool {
        guard let until = pausedUntil else { return false }
        return Date() < until
    }

    private let keychainService = "com.rachit.oneline"
    private let keychainAccount = "slack-token"
    private let pausedUntilKey = "slackPausedUntil"
    private let port: UInt16 = 21849
    private let redirectURI = "https://r2.rachitsingh.com/oneline/callback/index.html"

    private var listener: NWListener?
    private var serverTimeout: DispatchWorkItem?

    private var clientId: String {
        Bundle.main.object(forInfoDictionaryKey: "SlackClientID") as? String ?? ""
    }
    private var clientSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "SlackClientSecret") as? String ?? ""
    }

    private init() {
        isAuthenticated = loadToken() != nil
        if let saved = UserDefaults.standard.object(forKey: pausedUntilKey) as? Date {
            if Date() < saved {
                pausedUntil = saved
            } else {
                UserDefaults.standard.removeObject(forKey: pausedUntilKey)
            }
        }
    }

    // MARK: - OAuth

    func startOAuth() {
        startServer()

        var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "user_scope", value: "users.profile:write"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Local HTTP Server

    private func startServer() {
        stopServer()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            return
        }

        // Auto-shutdown after 5 minutes if no callback received
        let timeout = DispatchWorkItem { [weak self] in
            self?.stopServer()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timeout)
        serverTimeout = timeout
    }

    private func stopServer() {
        serverTimeout?.cancel()
        serverTimeout = nil
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse "GET /callback?code=xxx HTTP/1.1"
            guard let firstLine = request.components(separatedBy: "\r\n").first,
                  let path = firstLine.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: String(path)),
                  components.path == "/callback",
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                let response = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let html = "<html><body style=\"font-family:system-ui;padding:40px;text-align:center\">"
                + "<p>Connected to Slack! You can close this tab.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            self.stopServer()
            self.exchangeCode(code)
        }
    }

    private func exchangeCode(_ code: String) {
        let url = URL(string: "https://slack.com/api/oauth.v2.access")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = body.query?.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let authedUser = json["authed_user"] as? [String: Any],
                  let token = authedUser["access_token"] as? String else {
                return
            }
            DispatchQueue.main.async {
                self?.saveToken(token)
                self?.isAuthenticated = true
            }
        }.resume()
    }

    // MARK: - Status

    func updateStatus(text: String) {
        guard isAuthenticated, !isPaused, let token = loadToken() else { return }

        let statusText = String(text.prefix(100))
        let url = URL(string: "https://slack.com/api/users.profile.set")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "profile": [
                "status_text": statusText,
                "status_emoji": ":speech_balloon:",
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - Settings

    func disconnect() {
        deleteToken()
        isAuthenticated = false
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: pausedUntilKey)
    }

    func pauseForOneDay() {
        let until = Date().addingTimeInterval(86400)
        pausedUntil = until
        UserDefaults.standard.set(until, forKey: pausedUntilKey)
    }

    // MARK: - Keychain

    private func saveToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = token.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
