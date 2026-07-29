import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchPanelController?
    private var socketServer: SocketServer?
    private var approvalCoordinator: ApprovalCoordinator?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        UserDefaults.standard.register(defaults: [
            "soundsEnabled": true,
            "soundApproval": true,
            "soundQuestion": true,
            "soundDone": true,
            "panelWidth": 520.0
        ])

        let controller = NotchPanelController()
        controller.show()
        notchController = controller

        let coordinator = ApprovalCoordinator(state: controller.state)
        approvalCoordinator = coordinator

        controller.state.onOpenSettings = {
            SettingsWindowController.shared.show()
        }

        let server = SocketServer { [weak controller, weak coordinator] event, respond in
            if (event["hook_event_name"] as? String) == "PreToolUse", let coordinator {
                coordinator.handlePreToolUse(event, respond: respond)
            } else {
                controller?.state.apply(event: event)
                respond(["ok": true])
            }
        }
        do {
            try server.start()
            socketServer = server
        } catch {
            NSLog("Perch: failed to start socket server: \(error)")
        }

        HookInstaller.installAll()
        statusItemController = StatusItemController()

        // Warm the quota cache so the footer is ready on first expand
        UsageTracker.shared.refreshIfStale { [weak controller] snapshot in
            controller?.state.usage = snapshot
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    @objc private func screenParametersChanged() {
        notchController?.repositionOnNotchScreen()
    }
}
