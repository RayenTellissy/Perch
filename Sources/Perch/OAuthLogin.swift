import AppKit
import CryptoKit
import Foundation

// Browser-based PKCE login using Claude Code's public OAuth client — the
// user approves in claude.ai where they are already signed in, the code
// comes back on a localhost callback, and no terminal is involved
final class OAuthLogin {
    static let shared = OAuthLogin()

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let redirectURI = "http://localhost:54545/callback"
    private static let port: UInt16 = 54545

    private let queue = DispatchQueue(label: "com.perch.oauth")
    private var serverFD: Int32 = -1
    private var active = false

    func start(completion: @escaping (Bool) -> Void) {
        queue.async {
            guard !self.active else { return }
            self.active = true
            let finish: (Bool) -> Void = { success in
                self.closeServer()
                self.active = false
                DispatchQueue.main.async { completion(success) }
            }

            let verifier = Self.base64URL(Self.randomBytes(32))
            let state = Self.base64URL(Self.randomBytes(32))
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

            guard self.listen() else {
                finish(false)
                return
            }

            var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
            components.queryItems = [
                URLQueryItem(name: "code", value: "true"),
                URLQueryItem(name: "client_id", value: Self.clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
                URLQueryItem(name: "scope", value: "org:create_api_key user:profile user:inference"),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state)
            ]
            DispatchQueue.main.async {
                NSWorkspace.shared.open(components.url!)
            }

            guard let (code, returnedState) = self.waitForCallback(timeout: 300) else {
                finish(false)
                return
            }
            guard returnedState == state else {
                finish(false)
                return
            }
            finish(Self.exchange(code: code, state: state, verifier: verifier))
        }
    }

    private static func exchange(code: String, state: String, verifier: String) -> Bool {
        var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ])
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard
                (response as? HTTPURLResponse)?.statusCode == 200,
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessToken = json["access_token"] as? String
            else { return }
            UsageTracker.storeLogin(
                accessToken: accessToken,
                refreshToken: json["refresh_token"] as? String,
                expiresIn: (json["expires_in"] as? Double) ?? 3600
            )
            success = true
        }.resume()
        semaphore.wait()
        return success
    }

    // Minimal one-shot HTTP listener for the OAuth redirect
    private func listen() -> Bool {
        serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return false }
        var reuse: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Foundation.listen(serverFD, 1) == 0 else {
            closeServer()
            return false
        }
        return true
    }

    private func waitForCallback(timeout: TimeInterval) -> (code: String, state: String)? {
        var readSet = timeval(tv_sec: Int(timeout), tv_usec: 0)
        var fds = fd_set()
        __darwin_fd_set(serverFD, &fds)
        guard select(serverFD + 1, &fds, nil, nil, &readSet) > 0 else { return nil }

        let client = accept(serverFD, nil, nil)
        guard client >= 0 else { return nil }
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else { return nil }

        let request = String(decoding: buffer[0..<count], as: UTF8.self)
        guard
            let target = request.split(separator: " ").dropFirst().first,
            let components = URLComponents(string: String(target)),
            components.path == "/callback",
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            respond(client, body: "Login failed. You can close this tab.")
            return nil
        }
        respond(client, body: "Connected. You can close this tab and return to Perch.")
        return (code, state)
    }

    private func respond(_ client: Int32, body: String) {
        let html = "<html><body style=\"font-family:-apple-system;background:#000;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh\">\(body)</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        _ = response.withCString { write(client, $0, strlen($0)) }
    }

    private func closeServer() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
