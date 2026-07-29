import AppKit
import CoreText

enum FontRegistrar {
    static func registerBundledFonts() {
        guard let fontsDir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: fontsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
