import AppKit
import Foundation

// Renders the app icon from code: no binary assets in the repo.
// Usage: swift scripts/make-icon.swift <output-directory>
// Produces <dir>/AppIcon.iconset and <dir>/AppIcon.icns

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: make-icon.swift <output-directory>")
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = size / 1024.0
    let full = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    full.fill()

    // Squircle plate
    let inset = 44 * scale
    let plate = NSBezierPath(
        roundedRect: full.insetBy(dx: inset, dy: inset),
        xRadius: 224 * scale,
        yRadius: 224 * scale
    )

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.99, green: 0.36, blue: 0.30, alpha: 1.0),
        NSColor(srgbRed: 0.87, green: 0.16, blue: 0.35, alpha: 1.0),
        NSColor(srgbRed: 0.42, green: 0.24, blue: 0.86, alpha: 1.0)
    ])
    gradient?.draw(in: plate, angle: -62)

    // Soft top highlight
    NSGraphicsContext.saveGraphicsState()
    plate.setClip()
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0)
    ])
    highlight?.draw(
        from: NSPoint(x: 0, y: size),
        to: NSPoint(x: 0, y: size * 0.52),
        options: []
    )
    NSGraphicsContext.restoreGraphicsState()

    // Play mark
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 404 * scale, y: 420 * scale))
    play.line(to: NSPoint(x: 404 * scale, y: 742 * scale))
    play.line(to: NSPoint(x: 700 * scale, y: 581 * scale))
    play.close()
    play.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.97).setFill()
    play.fill()

    // Shelf lines
    let shelfTop = NSBezierPath(
        roundedRect: NSRect(x: 262 * scale, y: 318 * scale, width: 500 * scale, height: 46 * scale),
        xRadius: 23 * scale,
        yRadius: 23 * scale
    )
    NSColor.white.withAlphaComponent(0.55).setFill()
    shelfTop.fill()

    let shelfBottom = NSBezierPath(
        roundedRect: NSRect(x: 330 * scale, y: 226 * scale, width: 364 * scale, height: 40 * scale),
        xRadius: 20 * scale,
        yRadius: 20 * scale
    )
    NSColor.white.withAlphaComponent(0.28).setFill()
    shelfBottom.fill()

    return image
}

func pngData(from image: NSImage, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let master = drawIcon(size: 1024)
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, pixels) in variants {
    guard let data = pngData(from: master, pixelSize: pixels) else {
        print("failed to render \(name)")
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try? process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Wrote \(icns.path)")
} else {
    print("iconutil failed")
    exit(1)
}
