import AppKit
import Foundation

// Launches new agent sessions in a terminal from the notch
enum AgentController {
    static func launchSession(agent: String, directory: String) {
        let command = "cd \(shellQuoted(directory)) && \(agent)"
        if isRunning("com.googlecode.iterm2") || (!isRunning("com.apple.Terminal") && isInstalled("com.googlecode.iterm2")) {
            _ = runAppleScript("""
            tell application "iTerm2"
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(escaped(command))"
                end tell
                activate
            end tell
            """)
        } else {
            _ = runAppleScript("""
            tell application "Terminal"
                do script "\(escaped(command))"
                activate
            end tell
            """)
        }
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // osascript instead of NSAppleScript so callers can stay off the main
    // thread — Apple Event permission prompts and slow scripts must never
    // freeze the notch panel
    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
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
