import Foundation

// Decides whether a PreToolUse event should be gated behind a notch approval.
// Conservative by design: anything Claude Code would auto-allow, or anything
// we are unsure about, passes through to the normal permission flow.
enum PermissionRules {
    private static let gatedTools: Set<String> = ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit"]
    private static let editTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit"]

    static func shouldGate(_ event: [String: Any]) -> Bool {
        let tool = (event["tool_name"] as? String) ?? ""

        // Gating semantics are only verified for Claude Code
        guard ((event["fv_agent"] as? String) ?? "claude") == "claude" else { return false }

        // Only terminal sessions: GUI sessions (desktop app, IDE panes) have
        // their own approval UI and often auto-approve
        guard event["fv_tty"] != nil else { return false }

        // Questions prompt in every permission mode
        if tool == "AskUserQuestion" { return true }

        // Only gate when we positively know the session would prompt
        guard let mode = event["permission_mode"] as? String else { return false }
        switch mode {
        case "default":
            break
        case "acceptEdits":
            if editTools.contains(tool) { return false }
        default:
            return false
        }
        guard gatedTools.contains(tool) || tool.hasPrefix("mcp__") else { return false }

        let rules = loadRules(cwd: event["cwd"] as? String)
        let command = (event["tool_input"] as? [String: Any])?["command"] as? String

        // Deny rules stay Claude Code's job; allow rules mean no prompt would appear
        if ruleMatches(rules.deny, tool: tool, command: command) { return false }
        if ruleMatches(rules.allow, tool: tool, command: command) { return false }
        return true
    }

    static func ruleMatches(_ rules: [String], tool: String, command: String?) -> Bool {
        for rule in rules {
            if rule == tool || rule == "\(tool)(*)" { return true }
            guard rule.hasPrefix("\(tool)("), rule.hasSuffix(")") else { continue }
            guard tool == "Bash", let command else { continue }

            let spec = String(rule.dropFirst(tool.count + 1).dropLast())
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            if spec.hasSuffix(":*") {
                let prefix = String(spec.dropLast(2))
                if trimmed == prefix || trimmed.hasPrefix(prefix + " ") { return true }
            } else if trimmed == spec {
                return true
            }
        }
        return false
    }

    private static func loadRules(cwd: String?) -> (allow: [String], deny: [String]) {
        var candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/settings.json")
        ]
        if let cwd {
            let projectDir = URL(fileURLWithPath: cwd).appendingPathComponent(".claude")
            candidates.append(projectDir.appendingPathComponent("settings.json"))
            candidates.append(projectDir.appendingPathComponent("settings.local.json"))
        }

        var allow: [String] = []
        var deny: [String] = []
        for url in candidates {
            guard
                let data = try? Data(contentsOf: url),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let permissions = json["permissions"] as? [String: Any]
            else { continue }
            allow += (permissions["allow"] as? [String]) ?? []
            deny += (permissions["deny"] as? [String]) ?? []
        }
        return (allow, deny)
    }
}
