import Foundation

struct QuotaWindow {
    let label: String
    let utilization: Double
    let resetsAt: Date?
}

struct UsageSnapshot {
    var windows: [QuotaWindow] = []
    var needsLogin = false
    var computedAt = Date.distantPast
}

// Fetches remaining rate-limit quota from Anthropic's OAuth usage endpoint,
// authenticated with the Claude Code credentials already on this Mac.
// Expired tokens are refreshed with Claude Code's public OAuth client and the
// fresh pair is cached under this app's own support directory — the original
// keychain item is never modified
final class UsageTracker {
    static let shared = UsageTracker()

    private let queue = DispatchQueue(label: "com.perch.usage", qos: .utility)
    private var cached = UsageSnapshot()
    private let staleAfter: TimeInterval = 60

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Perch/claude-oauth.json")

    private struct Credentials {
        var accessToken: String
        var refreshToken: String?
        var expiresAtMS: Double?

        var isExpired: Bool {
            guard let expiresAtMS else { return false }
            return expiresAtMS / 1000 < Date().timeIntervalSince1970 + 60
        }
    }

    func refreshIfStale(completion: @escaping (UsageSnapshot) -> Void) {
        queue.async {
            if Date().timeIntervalSince(self.cached.computedAt) > self.staleAfter {
                self.cached = Self.fetch()
            }
            let snapshot = self.cached
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    func forceRefresh(completion: @escaping (UsageSnapshot) -> Void) {
        queue.async {
            self.cached = Self.fetch()
            let snapshot = self.cached
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    static func storeLogin(accessToken: String, refreshToken: String?, expiresIn: Double) {
        saveCache(Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMS: (Date().timeIntervalSince1970 + expiresIn) * 1000
        ))
    }

    private static func fetch() -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.computedAt = Date()

        guard var creds = loadCredentials() else {
            debugLog("no credentials found")
            snapshot.needsLogin = true
            return snapshot
        }
        if creds.isExpired {
            guard let refreshed = refresh(creds) else {
                snapshot.needsLogin = true
                return snapshot
            }
            creds = refreshed
        }

        var (status, body) = requestUsage(token: creds.accessToken)
        if status == 401, let refreshed = refresh(creds) {
            (status, body) = requestUsage(token: refreshed.accessToken)
        }
        if status == 401 { snapshot.needsLogin = true }
        guard
            status == 200,
            let body,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            debugLog("usage request failed, status \(status)")
            return snapshot
        }

        let windowKeys: [(String, String)] = [
            ("five_hour", "5h"),
            ("seven_day", "7d"),
            ("seven_day_opus", "7d Opus")
        ]
        for (key, label) in windowKeys {
            guard let window = json[key] as? [String: Any] else { continue }
            let utilization = (window["utilization"] as? Double)
                ?? (window["utilization"] as? Int).map(Double.init)
                ?? 0
            let resetsAt = (window["resets_at"] as? String).flatMap(parseDate)
            snapshot.windows.append(QuotaWindow(label: label, utilization: utilization, resetsAt: resetsAt))
        }
        return snapshot
    }

    private static func requestUsage(token: String) -> (Int, Data?) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 8
        return perform(request)
    }

    private static func refresh(_ creds: Credentials) -> Credentials? {
        guard let refreshToken = creds.refreshToken else {
            debugLog("token expired and no refresh token")
            return nil
        }
        var request = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
        request.timeoutInterval = 8

        let (status, body) = perform(request)
        guard
            status == 200,
            let body,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let accessToken = json["access_token"] as? String
        else {
            let detail = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            debugLog("token refresh failed, status \(status): \(detail.prefix(300))")
            return nil
        }

        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let refreshed = Credentials(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? refreshToken,
            expiresAtMS: (Date().timeIntervalSince1970 + expiresIn) * 1000
        )
        saveCache(refreshed)
        debugLog("token refreshed, valid \(Int(expiresIn / 60))m")
        return refreshed
    }

    private static func perform(_ request: URLRequest) -> (Int, Data?) {
        let semaphore = DispatchSemaphore(value: 0)
        var status = -1
        var body: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? -1
            body = data
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (status, body)
    }

    // Resolution order: our refreshed cache (if still current), the Claude
    // Code keychain item, then the JSON credentials file
    private static func loadCredentials() -> Credentials? {
        if let data = try? Data(contentsOf: cacheURL),
           let creds = parseCache(data), !creds.isExpired {
            return creds
        }
        if let data = keychainData(), let creds = parseClaude(data) {
            return creds
        }
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: fileURL), let creds = parseClaude(data) {
            return creds
        }
        // Expired cache still beats nothing — its refresh token may work
        if let data = try? Data(contentsOf: cacheURL) {
            return parseCache(data)
        }
        return nil
    }

    // Read through /usr/bin/security so the keychain grant attaches to
    // Apple's signed binary — a direct SecItemCopyMatching from this ad-hoc
    // signed app fails ACL validation on every rebuild
    private static func keychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !output.isEmpty else { return nil }
        return output
    }

    private static func parseClaude(_ data: Data) -> Credentials? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { return nil }
        return Credentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAtMS: oauth["expiresAt"] as? Double
        )
    }

    private static func parseCache(_ data: Data) -> Credentials? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["accessToken"] as? String
        else { return nil }
        return Credentials(
            accessToken: token,
            refreshToken: json["refreshToken"] as? String,
            expiresAtMS: json["expiresAtMS"] as? Double
        )
    }

    private static func saveCache(_ creds: Credentials) {
        var json: [String: Any] = ["accessToken": creds.accessToken]
        json["refreshToken"] = creds.refreshToken
        json["expiresAtMS"] = creds.expiresAtMS
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func debugLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/perch-usage.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
