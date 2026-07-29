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
        installOpenCodePlugin()
        installCursorHooks()
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

    // MARK: - Cursor (~/.cursor/hooks.json)
    //
    // Cursor's hooks file has its own shape: {"version": 1, "hooks":
    // {event: [{"command": …}]}}. Hooks fail open when the command prints
    // nothing, so observing events never blocks the agent. Payloads are
    // translated to the shared vocabulary in NotchState.

    static func installCursorHooks() {
        guard directoryExists(".cursor") else { return }
        let url = home.appendingPathComponent(".cursor/hooks.json")
        guard var file = readJSON(url, createIfMissing: true) else { return }

        var hooks = file["hooks"] as? [String: Any] ?? [:]
        // Strip our entries everywhere first so removed events don't linger
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { ($0["command"] as? String)?.contains("Perch") == true }
            hooks[event] = entries
        }
        // beforeReadFile is deliberately absent: its payload carries the full
        // file contents, and read activity comes from the transcript anyway
        let events = [
            "beforeSubmitPrompt", "beforeShellExecution", "afterShellExecution",
            "beforeMCPExecution", "afterMCPExecution", "afterFileEdit", "stop"
        ]
        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(["command": command(agent: "cursor")])
            hooks[event] = entries
        }
        file["hooks"] = hooks
        if file["version"] == nil { file["version"] = 1 }
        writeJSON(file, to: url)
    }

    // MARK: - OpenCode (~/.config/opencode/plugin[s]/perch.js)
    //
    // OpenCode has no JSON hook config — it loads JS plugins instead. The
    // generated plugin maps OpenCode's hook API onto the shared event
    // vocabulary and pipes each event through "Perch hook opencode", so the
    // socket client and terminal-location enrichment are reused unchanged.

    static func installOpenCodePlugin() {
        guard directoryExists(".config/opencode") else { return }
        // OpenCode scans both "plugin" and "plugins" — reuse whichever
        // already exists, defaulting to the documented "plugin"
        let dirName = directoryExists(".config/opencode/plugins")
            ? ".config/opencode/plugins"
            : ".config/opencode/plugin"
        let dir = home.appendingPathComponent(dirName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = openCodePlugin(
            binary: Bundle.main.executablePath ?? CommandLine.arguments[0]
        )
        try? Data(script.utf8).write(to: dir.appendingPathComponent("perch.js"))
    }

    private static func openCodePlugin(binary: String) -> String {
        let quoted = binary
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        // Auto-generated by Perch — edits will be overwritten on next launch
        import { spawn } from "node:child_process"

        const PERCH = "\(quoted)"

        // OpenCode tool ids are lowercase; map them back to the Claude-style
        // names Perch's descriptions are keyed on
        const TOOL_NAMES = {
          bash: "Bash", read: "Read", edit: "Edit", write: "Write",
          glob: "Glob", grep: "Grep", list: "List", patch: "Patch",
          task: "Task", multiedit: "MultiEdit", todowrite: "TodoWrite",
          todoread: "TodoRead", webfetch: "WebFetch", websearch: "WebSearch",
          question: "AskUserQuestion"
        }

        const toolName = (tool) => {
          if (!tool) return "Tool"
          if (TOOL_NAMES[tool]) return TOOL_NAMES[tool]
          return tool.charAt(0).toUpperCase() + tool.slice(1)
        }

        const toolInput = (args) => {
          const input = { ...(args || {}) }
          if (typeof input.filePath === "string" && !input.file_path) {
            input.file_path = input.filePath
          }
          return input
        }

        const send = (payload) => {
          try {
            const child = spawn(PERCH, ["hook", "opencode"], {
              stdio: ["pipe", "ignore", "ignore"]
            })
            child.on("error", () => {})
            child.stdin.on("error", () => {})
            child.stdin.end(JSON.stringify(payload))
            child.unref()
          } catch {}
        }

        export const PerchPlugin = async ({ directory }) => {
          const cwds = new Map()
          const titles = new Map()
          const subagents = new Set()
          // Only sessions the user actually prompted show up in the notch —
          // background and archived sessions on the event bus stay invisible
          const active = new Set()
          const lastStop = new Map()

          const base = (sessionID, extra) => {
            const payload = {
              session_id: sessionID,
              cwd: cwds.get(sessionID) || directory,
              ...extra
            }
            const title = titles.get(sessionID)
            if (title) payload.fv_title = title
            return payload
          }

          const remember = (info) => {
            if (!info || !info.id) return
            if (info.directory) cwds.set(info.id, info.directory)
            if (info.parentID) subagents.add(info.id)
            if (info.title && !info.title.startsWith("New session")) {
              titles.set(info.id, info.title)
            }
          }

          const forget = (sessionID) => {
            if (active.delete(sessionID)) {
              send(base(sessionID, { hook_event_name: "SessionEnd" }))
            }
            cwds.delete(sessionID)
            titles.delete(sessionID)
            subagents.delete(sessionID)
            lastStop.delete(sessionID)
          }

          return {
            "chat.message": async (input, output) => {
              const sessionID = (input && input.sessionID)
                || (output && output.message && output.message.sessionID)
              if (!sessionID || subagents.has(sessionID)) return
              active.add(sessionID)
              const prompt = ((output && output.parts) || [])
                .filter((part) => part.type === "text" && part.text)
                .map((part) => part.text)
                .join("\\n")
              send(base(sessionID, { hook_event_name: "UserPromptSubmit", prompt }))
            },
            "tool.execute.before": async (input, output) => {
              if (!input || !input.sessionID || subagents.has(input.sessionID)) return
              active.add(input.sessionID)
              send(base(input.sessionID, {
                hook_event_name: "PreToolUse",
                tool_name: toolName(input.tool),
                tool_input: toolInput(output && output.args)
              }))
            },
            "tool.execute.after": async (input) => {
              if (!input || !input.sessionID || !active.has(input.sessionID)) return
              send(base(input.sessionID, {
                hook_event_name: "PostToolUse",
                tool_name: toolName(input.tool)
              }))
            },
            event: async ({ event }) => {
              const type = event && event.type
              const props = (event && event.properties) || {}
              if ((type === "session.created" || type === "session.updated") && props.info) {
                remember(props.info)
                if (props.info.time && props.info.time.archived) forget(props.info.id)
                return
              }
              if (type === "session.deleted" && props.info) {
                forget(props.info.id)
                return
              }
              const idle = type === "session.idle"
                || (type === "session.status" && props.status && props.status.type === "idle")
              if (idle && props.sessionID && active.has(props.sessionID)) {
                const now = Date.now()
                if (now - (lastStop.get(props.sessionID) || 0) < 1500) return
                lastStop.set(props.sessionID, now)
                send(base(props.sessionID, { hook_event_name: "Stop" }))
                return
              }
              if ((type === "permission.updated" || type === "permission.asked")
                  && props.sessionID && active.has(props.sessionID)) {
                send(base(props.sessionID, {
                  hook_event_name: "Notification",
                  message: "Permission required in the terminal"
                }))
              }
            }
          }
        }
        """
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
