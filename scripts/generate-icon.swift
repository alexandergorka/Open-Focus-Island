import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let output = assets.appendingPathComponent("AppIcon.icns")
let iconset = root.appendingPathComponent(".build/iconset.iconset", isDirectory: true)
let manager = FileManager.default

guard !manager.fileExists(atPath: output.path) else {
    fatalError("Refusing to overwrite \(output.path)")
}
try manager.createDirectory(at: assets, withIntermediateDirectories: true)
if manager.fileExists(atPath: iconset.path) { try manager.removeItem(at: iconset) }
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)

let images: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in images {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
process.standardError = FileHandle.standardError
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed with status \(process.terminationStatus)") }

func drawIcon() {
    // macOS icon grid: 824-pt tile centered on the 1024 canvas, with a soft drop shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Calm sea: the island sits in it.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.05, green: 0.12, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.09, green: 0.31, blue: 0.40, alpha: 1),
    ])!.draw(in: tile, angle: 90)

    // The island: black, connected to the top edge like the app's notch panel.
    let island = NSRect(x: 252, y: 330, width: 520, height: 600)
    let r: CGFloat = 170
    let islandPath = NSBezierPath()
    islandPath.move(to: NSPoint(x: island.minX, y: island.maxY))
    islandPath.line(to: NSPoint(x: island.minX, y: island.minY + r))
    islandPath.appendArc(withCenter: NSPoint(x: island.minX + r, y: island.minY + r), radius: r, startAngle: 180, endAngle: 270)
    islandPath.line(to: NSPoint(x: island.maxX - r, y: island.minY))
    islandPath.appendArc(withCenter: NSPoint(x: island.maxX - r, y: island.minY + r), radius: r, startAngle: 270, endAngle: 360)
    islandPath.line(to: NSPoint(x: island.maxX, y: island.maxY))
    islandPath.close()
    NSColor.black.setFill()
    islandPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Focus ring: open arc (time remaining), green like the running indicator.
    let center = NSPoint(x: 512, y: 560)
    let radius: CGFloat = 148
    let lineWidth: CGFloat = 46
    let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    track.lineWidth = lineWidth
    NSColor(white: 1, alpha: 0.14).setStroke()
    track.stroke()

    let green = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 180, clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    green.setStroke()
    arc.stroke()

    // Running dot at the center.
    green.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()
}
