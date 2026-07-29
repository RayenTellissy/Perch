import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("soundsEnabled") private var soundsEnabled = true
    @AppStorage("soundApproval") private var soundApproval = true
    @AppStorage("soundQuestion") private var soundQuestion = true
    @AppStorage("soundDone") private var soundDone = true
    @AppStorage("panelWidth") private var panelWidth = 520.0

    @State private var rules: [(cwd: String, rule: String)] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Sounds") {
                Toggle("Play alert sounds", isOn: $soundsEnabled)
                soundRow("Approval needed", isOn: $soundApproval, sound: .approval)
                soundRow("Question asked", isOn: $soundQuestion, sound: .question)
                soundRow("Session finished", isOn: $soundDone, sound: .done)
            }

            Section("Panel") {
                HStack {
                    Slider(value: $panelWidth, in: 440...800, step: 20) {
                        Text("Expanded width")
                    }
                    Text("\(Int(panelWidth))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section("Always-allow rules") {
                if rules.isEmpty {
                    Text("No saved rules. Click \"Always Allow\" on an approval to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules, id: \.rule) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.rule)
                                    .font(.system(.body, design: .monospaced))
                                Text(abbreviate(item.cwd))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                AlwaysAllowStore.shared.remove(rule: item.rule, cwd: item.cwd)
                                reload()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
        .onAppear(perform: reload)
    }

    private func soundRow(_ title: String, isOn: Binding<Bool>, sound: SoundPlayer.Sound) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
                .disabled(!soundsEnabled)
            Button {
                SoundPlayer.shared.play(sound, force: true)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func reload() {
        rules = AlwaysAllowStore.shared.all
            .flatMap { cwd, list in list.map { (cwd: cwd, rule: $0) } }
            .sorted { $0.rule < $1.rule }
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Perch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
