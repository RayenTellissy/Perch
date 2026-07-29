import AppKit
import Combine
import SwiftUI

// Borderless panels refuse key status by default, which breaks button clicks.
// constrainFrameRect normally keeps windows below the menu bar, which leaves
// a gap between the island and the screen edge — return the rect untouched.
// Without accepting first mouse, a click while the panel isn't key only makes
// it key and gets swallowed — forcing a second click to actually hit controls
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class NotchPanelController {
    static var collapsedSize: NSSize {
        NSSize(width: 260, height: menuBarHeight)
    }

    // Matches the menu bar so the collapsed island sits flush with it:
    // the notch inset on notched screens, otherwise the menu bar strip height
    static var menuBarHeight: CGFloat {
        guard let screen = preferredScreen() else { return 24 }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }
    static var expandedSize: NSSize {
        let stored = UserDefaults.standard.double(forKey: "panelWidth")
        let width = stored >= 440 && stored <= 800 ? stored : 520
        return NSSize(width: width, height: 300)
    }

    private let panel: NSPanel
    let state = NotchState()
    private var expansionObserver: AnyCancellable?

    init() {
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = FirstMouseHostingView(rootView: NotchView(state: state))
        hosting.frame = NSRect(origin: .zero, size: Self.expandedSize)
        panel.contentView = hosting

        // SwiftUI keeps hover tracking, pointer styles, and gestures dormant
        // until the panel is genuinely key, which used to require a throwaway
        // first click. A nonactivating panel can take key without switching
        // apps, so grab it on expand and hand it back on collapse.
        expansionObserver = state.$isExpanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                guard let panel = self?.panel else { return }
                if expanded {
                    panel.makeKeyAndOrderFront(nil)
                } else if panel.isKeyWindow {
                    panel.resignKey()
                }
            }
    }

    func show() {
        repositionOnNotchScreen()
        panel.orderFrontRegardless()
    }

    // The panel always spans the full expanded size — transparent regions of a
    // clear non-opaque window pass mouse events through, and SwiftUI animates
    // the island itself so it grows out of the notch instead of the window
    // resizing around it
    func repositionOnNotchScreen() {
        guard let screen = Self.preferredScreen() else { return }
        panel.setFrame(frame(size: Self.expandedSize, on: screen), display: true)
    }

    private func frame(size: NSSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // The screen with a physical notch, otherwise the main screen
    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
