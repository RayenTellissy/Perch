import AppKit
import SwiftUI

// Central store for every user-tunable knob, persisted to UserDefaults
final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let defaults = UserDefaults.standard

    // MARK: - Appearance

    @Published var accentHex: String {
        didSet { defaults.set(accentHex, forKey: "accentHex") }
    }

    // "cube", "dot", "none"
    @Published var workingIndicator: String {
        didSet { defaults.set(workingIndicator, forKey: "workingIndicator") }
    }

    @Published var spinningBorderEnabled: Bool {
        didSet { defaults.set(spinningBorderEnabled, forKey: "spinningBorderEnabled") }
    }

    @Published var staggeredAnimations: Bool {
        didSet { defaults.set(staggeredAnimations, forKey: "staggeredAnimations") }
    }

    var accentColor: Color {
        Color(hex: accentHex)
    }

    // MARK: - Panel

    @Published var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: "panelWidth") }
    }

    @Published var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: "panelHeight") }
    }

    @Published var collapsedActiveWidth: Double {
        didSet { defaults.set(collapsedActiveWidth, forKey: "collapsedActiveWidth") }
    }

    @Published var hoverCollapseDelay: Double {
        didSet { defaults.set(hoverCollapseDelay, forKey: "hoverCollapseDelay") }
    }

    @Published var collapsedShowsActivity: Bool {
        didSet { defaults.set(collapsedShowsActivity, forKey: "collapsedShowsActivity") }
    }

    // MARK: - Behavior

    @Published var spotlightEnabled: Bool {
        didSet { defaults.set(spotlightEnabled, forKey: "spotlightEnabled") }
    }

    @Published var spotlightDuration: Double {
        didSet { defaults.set(spotlightDuration, forKey: "spotlightDuration") }
    }

    @Published var showUsageFooter: Bool {
        didSet { defaults.set(showUsageFooter, forKey: "showUsageFooter") }
    }

    @Published var showPromptLine: Bool {
        didSet { defaults.set(showPromptLine, forKey: "showPromptLine") }
    }

    @Published var showRelativeTime: Bool {
        didSet { defaults.set(showRelativeTime, forKey: "showRelativeTime") }
    }

    @Published var recentDirectoryLimit: Int {
        didSet { defaults.set(recentDirectoryLimit, forKey: "recentDirectoryLimit") }
    }

    @Published var defaultAgent: String {
        didSet { defaults.set(defaultAgent, forKey: "defaultAgent") }
    }

    // MARK: - Sounds

    @Published var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: "soundVolume") }
    }

    private init() {
        accentHex = defaults.string(forKey: "accentHex") ?? "F5A847"
        workingIndicator = defaults.string(forKey: "workingIndicator") ?? "cube"
        spinningBorderEnabled = defaults.object(forKey: "spinningBorderEnabled") as? Bool ?? true
        staggeredAnimations = defaults.object(forKey: "staggeredAnimations") as? Bool ?? true
        panelWidth = Self.clamp(defaults.object(forKey: "panelWidth") as? Double ?? 520, 440, 800)
        panelHeight = Self.clamp(defaults.object(forKey: "panelHeight") as? Double ?? 300, 240, 480)
        collapsedActiveWidth = Self.clamp(defaults.object(forKey: "collapsedActiveWidth") as? Double ?? 420, 300, 560)
        hoverCollapseDelay = Self.clamp(defaults.object(forKey: "hoverCollapseDelay") as? Double ?? 0.35, 0.1, 2.0)
        collapsedShowsActivity = defaults.object(forKey: "collapsedShowsActivity") as? Bool ?? true
        spotlightEnabled = defaults.object(forKey: "spotlightEnabled") as? Bool ?? true
        spotlightDuration = Self.clamp(defaults.object(forKey: "spotlightDuration") as? Double ?? 30, 5, 120)
        showUsageFooter = defaults.object(forKey: "showUsageFooter") as? Bool ?? true
        showPromptLine = defaults.object(forKey: "showPromptLine") as? Bool ?? true
        showRelativeTime = defaults.object(forKey: "showRelativeTime") as? Bool ?? true
        recentDirectoryLimit = Self.clampInt(defaults.object(forKey: "recentDirectoryLimit") as? Int ?? 8, 3, 20)
        defaultAgent = defaults.string(forKey: "defaultAgent") ?? "claude"
        soundVolume = Self.clamp(defaults.object(forKey: "soundVolume") as? Double ?? 1.0, 0, 1)
    }

    func resetToDefaults() {
        accentHex = "F5A847"
        workingIndicator = "cube"
        spinningBorderEnabled = true
        staggeredAnimations = true
        panelWidth = 520
        panelHeight = 300
        collapsedActiveWidth = 420
        hoverCollapseDelay = 0.35
        collapsedShowsActivity = true
        spotlightEnabled = true
        spotlightDuration = 30
        showUsageFooter = true
        showPromptLine = true
        showRelativeTime = true
        recentDirectoryLimit = 8
        defaultAgent = "claude"
        soundVolume = 1.0
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }

    private static func clampInt(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return "FFFFFF" }
        return String(
            format: "%02X%02X%02X",
            Int(round(srgb.redComponent * 255)),
            Int(round(srgb.greenComponent * 255)),
            Int(round(srgb.blueComponent * 255))
        )
    }
}
