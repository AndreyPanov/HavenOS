#!/usr/bin/env swift
import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/HavenApp/Resources", isDirectory: true)
let temporaryIconset = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("HavenIcon.iconset", isDirectory: true)
let icnsURL = resources.appendingPathComponent("HavenIcon.icns")
let previewURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("haven-icon-preview.png")

try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
try? fileManager.removeItem(at: temporaryIconset)
try fileManager.createDirectory(at: temporaryIconset, withIntermediateDirectories: true)

struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        self.red = CGFloat((hex >> 16) & 0xff) / 255
        self.green = CGFloat((hex >> 8) & 0xff) / 255
        self.blue = CGFloat(hex & 0xff) / 255
        self.alpha = alpha
    }

    var color: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

func savePNG(size: Int, to url: URL, drawing: (CGFloat) -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(
            domain: "HavenIconGenerator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap for \(url.path)"]
        )
    }

    bitmap.size = NSSize(width: size, height: size)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "HavenIconGenerator",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not create drawing context for \(url.path)"]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.shouldAntialias = true
    drawing(CGFloat(size))
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "HavenIconGenerator",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG for \(url.path)"]
        )
    }

    try data.write(to: url, options: .atomic)
}

func drawLandingMark(in rect: CGRect, strokeColor: NSColor, lineWidth: CGFloat) {
    let unit = rect.width / 38
    let stroke = lineWidth * unit

    func cssRect(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX + left * unit,
            y: rect.maxY - (top + height) * unit,
            width: width * unit,
            height: height * unit
        )
    }

    strokeColor.setStroke()

    let body = cssRect(left: 10, top: 15, width: 18, height: 11)
    let bodyRadius = 5.3 * unit
    let bodyPath = NSBezierPath()
    bodyPath.move(to: CGPoint(x: body.minX, y: body.maxY))
    bodyPath.line(to: CGPoint(x: body.minX, y: body.minY + bodyRadius))
    bodyPath.curve(
        to: CGPoint(x: body.minX + bodyRadius, y: body.minY),
        controlPoint1: CGPoint(x: body.minX, y: body.minY + bodyRadius * 0.42),
        controlPoint2: CGPoint(x: body.minX + bodyRadius * 0.42, y: body.minY)
    )
    bodyPath.line(to: CGPoint(x: body.maxX - bodyRadius, y: body.minY))
    bodyPath.curve(
        to: CGPoint(x: body.maxX, y: body.minY + bodyRadius),
        controlPoint1: CGPoint(x: body.maxX - bodyRadius * 0.42, y: body.minY),
        controlPoint2: CGPoint(x: body.maxX, y: body.minY + bodyRadius * 0.42)
    )
    bodyPath.line(to: CGPoint(x: body.maxX, y: body.maxY))
    bodyPath.lineWidth = stroke
    bodyPath.lineCapStyle = .round
    bodyPath.lineJoinStyle = .round
    bodyPath.stroke()

    let shackle = cssRect(left: 14, top: 10, width: 10, height: 9)
    let shacklePath = NSBezierPath()
    shacklePath.move(to: CGPoint(x: shackle.minX, y: shackle.minY))
    shacklePath.line(to: CGPoint(x: shackle.minX, y: shackle.maxY - 3.6 * unit))
    shacklePath.curve(
        to: CGPoint(x: shackle.maxX, y: shackle.maxY - 3.6 * unit),
        controlPoint1: CGPoint(x: shackle.minX, y: shackle.maxY + 0.7 * unit),
        controlPoint2: CGPoint(x: shackle.maxX, y: shackle.maxY + 0.7 * unit)
    )
    shacklePath.line(to: CGPoint(x: shackle.maxX, y: shackle.minY))
    shacklePath.lineWidth = stroke
    shacklePath.lineCapStyle = .round
    shacklePath.lineJoinStyle = .round
    shacklePath.stroke()
}

func drawAppIcon(size: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let scale = size / 1024
    let iconRect = CGRect(
        x: 86 * scale,
        y: 86 * scale,
        width: 852 * scale,
        height: 852 * scale
    )
    let radius = 268 * scale
    let background = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -24 * scale),
        blur: 62 * scale,
        color: NSColor.black.withAlphaComponent(0.28).cgColor
    )
    RGB(0x151515).color.setFill()
    background.fill()
    context.restoreGState()

    background.addClip()
    NSGradient(colors: [
        RGB(0x151515).color,
        RGB(0x4b463d).color,
    ])?.draw(in: background, angle: -35)

    NSColor.white.withAlphaComponent(0.18).setStroke()
    background.lineWidth = max(1, 2 * scale)
    background.stroke()

    drawLandingMark(
        in: iconRect,
        strokeColor: NSColor.white.withAlphaComponent(0.9),
        lineWidth: 2.05
    )
}

func drawMenuTemplate(size: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let rect = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let background = NSBezierPath(roundedRect: rect, xRadius: size * 0.25, yRadius: size * 0.25)

    NSColor.black.setFill()
    background.fill()

    context.saveGState()
    context.setBlendMode(.clear)
    drawLandingMark(
        in: rect.insetBy(dx: size * 0.08, dy: size * 0.08),
        strokeColor: .black,
        lineWidth: 2.25
    )
    context.restoreGState()
}

let iconFiles: [(name: String, size: CGFloat)] = [
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

for file in iconFiles {
    try savePNG(size: Int(file.size), to: temporaryIconset.appendingPathComponent(file.name)) { size in
        drawAppIcon(size: size)
    }
}

try savePNG(size: 1024, to: previewURL) { size in
    drawAppIcon(size: size)
}
try savePNG(size: 18, to: resources.appendingPathComponent("HavenMenuTemplate.png")) { size in
    drawMenuTemplate(size: size)
}
try savePNG(size: 36, to: resources.appendingPathComponent("HavenMenuTemplate@2x.png")) { size in
    drawMenuTemplate(size: size)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsURL.path, temporaryIconset.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(
        domain: "HavenIconGenerator",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"]
    )
}

print("Generated \(icnsURL.path)")
print("Generated \(resources.appendingPathComponent("HavenMenuTemplate@2x.png").path)")
print("Preview \(previewURL.path)")
