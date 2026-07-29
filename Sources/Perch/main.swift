import AppKit

if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "hook" {
    let agent = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "claude"
    HookClient.runAndExit(agent: agent)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
