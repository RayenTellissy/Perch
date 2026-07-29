import AppKit

// Renders the Perch app icon: a dark rounded square with a notch
// at the top and three session-status bars. Usage: swift make-icon.swift out.png

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

let bgRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 196, yRadius: 196)

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.20, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
)
gradient?.draw(in: bg, angle: -90)

NSGraphicsContext.current?.saveGraphicsState()
bg.addClip()

// Notch hanging from the top edge
let notch = NSBezierPath(
    roundedRect: NSRect(x: 312, y: 836, width: 400, height: 190),
    xRadius: 48,
    yRadius: 48
)
NSColor.black.setFill()
notch.fill()

// Session bars with status dots
let barX: CGFloat = 232
let barWidth: CGFloat = 560
let barHeight: CGFloat = 108
let dotColors: [NSColor] = [
    NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.45, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.60, alpha: 1)
]

for (index, color) in dotColors.enumerated() {
    let y = 560 - CGFloat(index) * 168
    let bar = NSBezierPath(
        roundedRect: NSRect(x: barX, y: y, width: barWidth, height: barHeight),
        xRadius: 34,
        yRadius: 34
    )
    NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
    bar.fill()

    let dot = NSBezierPath(ovalIn: NSRect(x: barX + 36, y: y + 34, width: 40, height: 40))
    color.setFill()
    dot.fill()

    let line = NSBezierPath(
        roundedRect: NSRect(x: barX + 116, y: y + 42, width: 340 - CGFloat(index) * 60, height: 24),
        xRadius: 12,
        yRadius: 12
    )
    NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
    line.fill()
}

NSGraphicsContext.current?.restoreGraphicsState()
image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("failed to render icon")
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
