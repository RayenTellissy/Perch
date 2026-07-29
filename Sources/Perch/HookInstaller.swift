import Foundation

// Merges Perch hook entries into each installed agent's config,
// preserving everything else. One-time backups are written on first install.
enum HookInstaller {
    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func installAll() {
        installClaudeHooks()
        installCodexHooks()
        installGeminiHooks()
    }

    // MARK: - Claude Code (~/.claude/settings.json)

    static func installClaudeHooks() {
        let url = home.appendingPathComponent(".claude/settings.json")
        guard var settings = readJSON(url, createIfMissing: true) else { return }

        let entry: [String: Any] = ["type": "command", "command": command(agent: "claude")]
        settings["hooks"] = merged(
            settings["hooks"] as? [String: Any] ?? [:],
            events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"],
            entry: entry,
            matcherEvents: ["PreToolUse", "PostToolUse"],
            timeoutFor: { $0 == "PreToolUse" ? 90 : 10 }
        )
        writeJSON(settings, to: url)
    }

    // MARK: - Codex CLI (~/.codex/hooks.json)

    static func installCodexHooks() {
        guard directoryExists(".codex") else { return }
        let url = home.appendingPathComponent(".codex/hooks.json")
        guard var file = readJSON(url, createIfMissing: true) else { return }

        let entry: [String: Any] = ["type": "command", "command": command(agent: "codex")]
        file["hooks"] = merged(
            file["hooks"] as? [String: Any] ?? [:],
            events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"],
            entry: entry,
            matcherEvents: [],
            timeoutFor: { _ in 10 }
        )
        writeJSON(file, to: url)
    }

    // MARK: - Gemini CLI (~/.gemini/settings.json, timeouts in ms)

    static func installGeminiHooks() {
        guard directoryExists(".gemini") else { return }
        let url = home.appendingPathComponent(".gemini/settings.json")
        guard var settings = readJSON(url, createIfMissing: true) else { return }

        let entry: [String: Any] = [
            "type": "command",
            "command": command(agent: "gemini"),
            "name": "Perch"
        ]
        settings["hooks"] = merged(
            settings["hooks"] as? [String: Any] ?? [:],
            events: ["SessionStart", "BeforeTool", "AfterTool", "AfterAgent", "Notification", "SessionEnd"],
            entry: entry,
            matcherEvents: [],
            timeoutFor: { _ in 10000 }
        )
        writeJSON(settings, to: url)
    }

    // MARK: - Shared

    private static func merged(
        _ hooks: [String: Any],
        events: [String],
        entry: [String: Any],
        matcherEvents: Set<String>,
        timeoutFor: (String) -> Int
    ) -> [String: Any] {
        var hooks = hooks
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var group = group
                var entries = group["hooks"] as? [[String: Any]] ?? []
                entries.removeAll { item in
                    (item["command"] as? String)?.contains("Perch") == true
                }
                if entries.isEmpty { return nil }
                group["hooks"] = entries
                return group
            }

            var item = entry
            item["timeout"] = timeoutFor(event)
            var group: [String: Any] = ["hooks": [item]]
            if matcherEvents.contains(event) {
                group["matcher"] = "*"
            }
            groups.append(group)
            hooks[event] = groups
        }
        return hooks
    }

    private static func command(agent: String) -> String {
        "\"\(Bundle.main.executablePath ?? CommandLine.arguments[0])\" hook \(agent)"
    }

    private static func directoryExists(_ name: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: home.appendingPathComponent(name).path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private static func readJSON(_ url: URL, createIfMissing: Bool) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else {
            return createIfMissing ? [:] : nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Never clobber a file we cannot parse
            return nil
        }
        let backup = url.appendingPathExtension("perch-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? data.write(to: backup)
        }
        return json
    }

    private static func writeJSON(_ json: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }
}
