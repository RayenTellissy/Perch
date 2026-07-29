import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            PanelSettingsView()
                .tabItem { Label("Panel", systemImage: "rectangle.topthird.inset.filled") }
            BehaviorSettingsView()
                .tabItem { Label("Behavior", systemImage: "sparkles") }
            SoundSettingsView()
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            RulesSettingsView()
                .tabItem { Label("Rules", systemImage: "checkmark.shield") }
        }
        .frame(width: 500, height: 480)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack {
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Startup") {
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

            Section("New sessions") {
                Picker("Default agent", selection: $prefs.defaultAgent) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                    Text("Gemini").tag("gemini")
                    Text("OpenCode").tag("opencode")
                    Text("Cursor").tag("cursor-agent")
                }
                Stepper(
                    "Recent folders shown: \(prefs.recentDirectoryLimit)",
                    value: $prefs.recentDirectoryLimit,
                    in: 3...20
                )
            }

            Section {
                Button("Reset all settings to defaults") {
                    prefs.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject private var prefs = Prefs.shared

    private static let presets: [(name: String, hex: String)] = [
        ("Amber", "F5A847"),
        ("Blue", "5AA2F5"),
        ("Green", "5FD48A"),
        ("Purple", "A98BF5"),
        ("Pink", "F57AB0"),
        ("Silver", "C7C7C7")
    ]

    private var accentBinding: Binding<Color> {
        Binding(
            get: { prefs.accentColor },
            set: { prefs.accentHex = $0.hexString }
        )
    }

    var body: some View {
        Form {
            Section("Accent color") {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.hex) { preset in
                        Button {
                            prefs.accentHex = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if prefs.accentHex == preset.hex {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                    Spacer()
                    ColorPicker("Custom", selection: accentBinding, supportsOpacity: false)
                        .labelsHidden()
                }
                Text("Used for approvals, questions, and agent badges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Working indicator") {
                Picker("Style", selection: $prefs.workingIndicator) {
                    Text("Rubik's cube").tag("cube")
                    Text("Pulsing dot").tag("dot")
                    Text("Static square").tag("none")
                }
                .pickerStyle(.segmented)
                Toggle("Spinning border on working sessions", isOn: $prefs.spinningBorderEnabled)
            }

            Section("Motion") {
                Toggle("Staggered appear animations", isOn: $prefs.staggeredAnimations)
            }
        }
        .formStyle(.grouped)
    }
}

struct PanelSettingsView: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Expanded panel") {
                SliderRow(
                    title: "Width",
                    value: $prefs.panelWidth,
                    range: 440...800,
                    step: 20
                ) { "\(Int($0))pt" }
                SliderRow(
                    title: "Height",
                    value: $prefs.panelHeight,
                    range: 240...480,
                    step: 20
                ) { "\(Int($0))pt" }
            }

            Section("Collapsed island") {
                Toggle("Show activity while collapsed", isOn: $prefs.collapsedShowsActivity)
                SliderRow(
                    title: "Active width",
                    value: $prefs.collapsedActiveWidth,
                    range: 300...560,
                    step: 20
                ) { "\(Int($0))pt" }
                .disabled(!prefs.collapsedShowsActivity)
            }

            Section("Hover") {
                SliderRow(
                    title: "Collapse delay",
                    value: $prefs.hoverCollapseDelay,
                    range: 0.1...2.0,
                    step: 0.05
                ) { String(format: "%.2fs", $0) }
                Text("How long the panel stays open after the cursor leaves")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct BehaviorSettingsView: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Finished sessions") {
                Toggle("Show response spotlight when a session finishes", isOn: $prefs.spotlightEnabled)
                SliderRow(
                    title: "Auto-dismiss after",
                    value: $prefs.spotlightDuration,
                    range: 5...120,
                    step: 5
                ) { "\(Int($0))s" }
                .disabled(!prefs.spotlightEnabled)
            }

            Section("Session rows") {
                Toggle("Show last prompt", isOn: $prefs.showPromptLine)
                Toggle("Show relative timestamps", isOn: $prefs.showRelativeTime)
            }

            Section("Footer") {
                Toggle("Show usage quota footer", isOn: $prefs.showUsageFooter)
            }
        }
        .formStyle(.grouped)
    }
}

struct SoundSettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @AppStorage("soundsEnabled") private var soundsEnabled = true
    @AppStorage("soundApproval") private var soundApproval = true
    @AppStorage("soundQuestion") private var soundQuestion = true
    @AppStorage("soundDone") private var soundDone = true

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Play alert sounds", isOn: $soundsEnabled)
                soundRow("Approval needed", isOn: $soundApproval, sound: .approval)
                soundRow("Question asked", isOn: $soundQuestion, sound: .question)
                soundRow("Session finished", isOn: $soundDone, sound: .done)
            }

            Section("Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $prefs.soundVolume, in: 0...1)
                        .disabled(!soundsEnabled)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                    Text("\(Int(prefs.soundVolume * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
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
}

struct RulesSettingsView: View {
    @State private var rules: [(cwd: String, rule: String)] = []

    var body: some View {
        Form {
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
        .onAppear(perform: reload)
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
