import Foundation

// Per-project rules created from the "Always Allow" button, kept in the
// app's own store so they apply immediately to running sessions
final class AlwaysAllowStore {
    static let shared = AlwaysAllowStore()

    private let url: URL
    private var rulesByProject: [String: [String]]

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("always-allow.json")

        if let data = try? Data(contentsOf: url),
           let stored = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] {
            rulesByProject = stored
        } else {
            rulesByProject = [:]
        }
    }

    func matches(_ event: [String: Any]) -> Bool {
        guard let cwd = event["cwd"] as? String, let rules = rulesByProject[cwd], !rules.isEmpty else {
            return false
        }
        let tool = (event["tool_name"] as? String) ?? ""
        let command = (event["tool_input"] as? [String: Any])?["command"] as? String
        return PermissionRules.ruleMatches(rules, tool: tool, command: command)
    }

    var all: [String: [String]] {
        rulesByProject
    }

    func add(rule: String, cwd: String) {
        var rules = rulesByProject[cwd] ?? []
        guard !rules.contains(rule) else { return }
        rules.append(rule)
        rulesByProject[cwd] = rules
        save()
    }

    func remove(rule: String, cwd: String) {
        var rules = rulesByProject[cwd] ?? []
        rules.removeAll { $0 == rule }
        if rules.isEmpty {
            rulesByProject.removeValue(forKey: cwd)
        } else {
            rulesByProject[cwd] = rules
        }
        save()
    }

    private func save() {
        if let data = try? JSONSerialization.data(
            withJSONObject: rulesByProject,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: url)
        }
    }

    // A reasonable rule for "always allow this kind of call": command-prefix
    // rules for Bash, tool-level rules for everything else
    static func rule(for event: [String: Any]) -> String? {
        guard let tool = event["tool_name"] as? String else { return nil }
        guard tool == "Bash" else { return tool }
        let rawCommand = (event["tool_input"] as? [String: Any])?["command"] as? String
        guard let command = rawCommand?.trimmingCharacters(in: .whitespaces), !command.isEmpty else {
            return nil
        }

        let tokens = command.split(separator: " ").map(String.init)
        let twoTokenRunners: Set<String> = [
            "git", "npm", "pnpm", "yarn", "cargo", "docker", "brew",
            "swift", "go", "npx", "bundle", "rails", "make", "pip", "pip3"
        ]
        if tokens.count > 1, twoTokenRunners.contains(tokens[0]),
           !tokens[1].hasPrefix("-") {
            return "Bash(\(tokens[0]) \(tokens[1]):*)"
        }
        return "Bash(\(tokens[0]):*)"
    }
}
