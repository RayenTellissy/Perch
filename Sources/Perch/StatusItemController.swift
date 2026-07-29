import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let soundsItem = NSMenuItem(
        title: "Play Alert Sounds",
        action: #selector(toggleSounds),
        keyEquivalent: ""
    )

    override init() {
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Perch"
        )
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        soundsItem.target = self
        menu.addItem(soundsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Perch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        soundsItem.state = UserDefaults.standard.bool(forKey: "soundsEnabled") ? .on : .off
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleSounds() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "soundsEnabled"), forKey: "soundsEnabled")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
