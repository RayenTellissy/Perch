import AppKit
import CoreText

enum FontRegistrar {
    static func registerBundledFonts() {
        for dir in candidateDirectories() {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ), !files.isEmpty else { continue }

            for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            return
        }
    }

    // App bundle first; then next to the executable and the source-tree
    // Resources folder so `swift run` builds get real fonts too
    private static func candidateDirectories() -> [URL] {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("Fonts"))
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let buildDir = executable.deletingLastPathComponent()
        dirs.append(buildDir.appendingPathComponent("Fonts"))
        dirs.append(
            buildDir
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Fonts")
        )
        return dirs
    }
}
