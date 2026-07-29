import Foundation

// Invoked by agent hooks as "Perch hook": forwards the event JSON
// from stdin to the running app over the Unix socket. For PreToolUse it
// waits for a notch decision and emits Claude Code hook output; for every
// other event it fires and forgets. Always exits 0 so a missing or busy
// app never blocks the agent.
enum HookClient {
    static func runAndExit(agent: String) -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard var json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
        json["fv_agent"] = agent
        enrich(&json)
        guard var payload = try? JSONSerialization.data(withJSONObject: json) else { exit(0) }
        payload.append(0x0A)

        // Only Claude Code PreToolUse can be gated, so only it waits for a click
        let isPreToolUse = (json["hook_event_name"] as? String) == "PreToolUse" && agent == "claude"

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { exit(0) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard (try? SocketServer.copyPath(SocketServer.socketPath, into: &addr)) != nil else { exit(0) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, size)
            }
        }
        guard connected == 0 else { exit(0) }

        payload.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }

        // Approval clicks can take a while; everything else answers instantly
        var timeout = timeval(tv_sec: isPreToolUse ? 60 : 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while data.count < 1_048_576 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if buffer[..<n].contains(0x0A) { break }
        }

        if isPreToolUse,
           let line = data.split(separator: 0x0A).first,
           let response = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
           let action = response["action"] as? String,
           action == "allow" || action == "deny" {
            emitDecision(action, reason: response["reason"] as? String)
        }

        exit(0)
    }

    // Location metadata for terminal jumping, captured from our own process
    // tree since hooks run as children of the agent's process
    private static func enrich(_ json: inout [String: Any]) {
        let pid = getpid()
        if let tty = ProcessTree.ttyPath(startingFrom: pid) {
            json["fv_tty"] = tty
        }
        if let terminal = ProcessTree.terminalApp(startingFrom: pid) {
            json["fv_term_pid"] = Int(terminal.pid)
            json["fv_term_path"] = terminal.path
        }
        if ProcessInfo.processInfo.environment["TMUX"] != nil,
           let pane = ProcessInfo.processInfo.environment["TMUX_PANE"] {
            json["fv_tmux_pane"] = pane
        }
        if let agent = agentProcess(startingFrom: pid) {
            json["fv_agent_pid"] = Int(agent.pid)
            json["fv_agent_path"] = agent.path
        }
    }

    // Hooks run as children of the agent (usually via a shell wrapper), so
    // the first non-shell ancestor above this process is the agent itself.
    // The executable path travels along so signals can verify the pid was
    // not recycled by an unrelated process.
    private static func agentProcess(startingFrom pid: pid_t) -> (pid: pid_t, path: String)? {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "login"]
        for ancestor in ProcessTree.ancestors(of: pid).dropFirst() {
            guard let path = ProcessTree.path(for: ancestor) else { continue }
            let name = (path as NSString).lastPathComponent
            if shells.contains(name) { continue }
            return (ancestor, path)
        }
        return nil
    }

    private static func emitDecision(_ action: String, reason: String?) {
        let fallback = action == "allow"
            ? "Approved from the Perch notch"
            : "Denied from the Perch notch"
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": action,
                "permissionDecisionReason": reason ?? fallback
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}
