import AppKit
import Foundation

enum TerminalJumper {
    static func debugLog(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/perch-jump.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    static func jump(to session: AgentSession) {
        debugLog("jump session=\(session.id) tmux=\(session.tmuxPane ?? "-") tty=\(session.tty ?? "-") termPID=\(session.terminalAppPID.map(String.init) ?? "-") termPath=\(session.terminalAppPath ?? "-")")

        if let pane = session.tmuxPane, jumpTmux(pane: pane) {
            return
        }

        let termPath = session.terminalAppPath ?? ""
        if let tty = session.tty {
            if termPath.contains("Terminal.app"), selectAppleTerminalTab(tty: tty) { return }
            if termPath.contains("iTerm"), selectITermSession(tty: tty) { return }
        }

        activateTerminalApp(pid: session.terminalAppPID)
    }

    private static func activateTerminalApp(pid: Int32?) {
        guard let pid else {
            debugLog("no terminal pid recorded")
            return
        }
        guard let app = hostApplication(startingFrom: pid) else {
            debugLog("no activatable app above pid \(pid)")
            return
        }
        debugLog("activating \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier)")
        if app.isHidden { app.unhide() }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
        }
        let activated = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        debugLog("activate returned \(activated)")
        // Cooperative activation on macOS 14+ often ignores activate() from a
        // background app even when it returns true — openApplication with
        // activates is honored unconditionally, so always follow up with it
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { debugLog("openApplication error: \(error)") }
            }
        }
    }

    // The recorded pid may be a non-GUI helper (e.g. the Claude desktop
    // app's bundled CLI) — climb the tree to the nearest activatable app
    private static func hostApplication(startingFrom pid: pid_t) -> NSRunningApplication? {
        for ancestor in ProcessTree.ancestors(of: pid) {
            if let app = NSRunningApplication(processIdentifier: ancestor),
               app.activationPolicy == .regular {
                return app
            }
        }
        return nil
    }

    // MARK: - Apple Terminal

    private static func selectAppleTerminalTab(tty: String) -> Bool {
        runAppleScript("""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "notfound"
        """) == "ok"
    }

    // MARK: - iTerm2

    private static func selectITermSession(tty: String) -> Bool {
        runAppleScript("""
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "notfound"
        """) == "ok"
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("Perch: AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }

    // MARK: - tmux

    private static func jumpTmux(pane: String) -> Bool {
        guard let tmux = tmuxBinary() else { return false }

        guard runCommand(tmux, ["select-pane", "-t", pane]) else { return false }
        _ = runCommand(tmux, ["select-window", "-t", pane])
        if let sessionName = commandOutput(tmux, ["display-message", "-p", "-t", pane, "#{session_name}"]) {
            _ = runCommand(tmux, ["switch-client", "-t", sessionName])
        }

        // Focus the GUI terminal hosting the first attached tmux client
        if let clientPID = commandOutput(tmux, ["list-clients", "-F", "#{client_pid}"])?
            .split(separator: "\n").first.flatMap({ Int32($0) }),
           let terminal = ProcessTree.terminalApp(startingFrom: clientPID) {
            activateTerminalApp(pid: terminal.pid)
        }
        return true
    }

    private static func tmuxBinary() -> String? {
        [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    private static func runCommand(_ binary: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func commandOutput(_ binary: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
