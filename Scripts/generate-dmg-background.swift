#!/usr/bin/env swift
import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let outputURL = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? root.appendingPathComponent(".build/app/HavenDmgBackground.png")
let iconURL = root.appendingPathComponent("Sources/HavenApp/Resources/HavenIcon.icns")

try fileManager.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let canvasWidth = 920
let canvasHeight = 580

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawText(
    _ text: String,
    at point: CGPoint,
    font: NSFont,
    color textColor: NSColor,
    alignment: NSTextAlignment = .center,
    width: CGFloat = 220
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
    ]
    let string = NSString(string: text)
    string.draw(
        in: CGRect(x: point.x - width / 2, y: point.y, width: width, height: 32),
        withAttributes: attributes
    )
}

func drawGrid(in rect: CGRect) {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.clip(to: rect)

    color(0xd9d4ca, alpha: 0.36).setStroke()
    for x in stride(from: rect.minX, through: rect.maxX, by: 10) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.line(to: CGPoint(x: x, y: rect.maxY))
        path.lineWidth = 0.5
        path.stroke()
    }

    for y in stride(from: rect.minY, through: rect.maxY, by: 10) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.line(to: CGPoint(x: rect.maxX, y: y))
        path.lineWidth = 0.5
        path.stroke()
    }

    color(0xc4beb2, alpha: 0.42).setStroke()
    for x in stride(from: rect.minX, through: rect.maxX, by: 44) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x - 5, y: rect.midY))
        path.line(to: CGPoint(x: x + 5, y: rect.midY))
        path.move(to: CGPoint(x: x, y: rect.midY - 5))
        path.line(to: CGPoint(x: x, y: rect.midY + 5))
        path.lineWidth = 0.6
        path.stroke()
    }

    for y in stride(from: rect.minY + 30, through: rect.maxY, by: 44) {
        for x in stride(from: rect.minX + 40, through: rect.maxX, by: 44) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x - 4, y: y))
            path.line(to: CGPoint(x: x + 4, y: y))
            path.move(to: CGPoint(x: x, y: y - 4))
            path.line(to: CGPoint(x: x, y: y + 4))
            path.lineWidth = 0.55
            path.stroke()
        }
    }

    context.restoreGState()
}

func drawApplicationFolder(in rect: CGRect) {
    let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    folderIcon.size = rect.size

    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.16).cgColor)
    folderIcon.draw(in: rect)
    context.restoreGState()
}

func drawHavenIcon(in rect: CGRect) {
    guard let image = NSImage(contentsOf: iconURL) else { return }
    image.size = rect.size

    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    image.draw(in: rect)
    context.restoreGState()
}

func drawArrowTrail(centerY: CGFloat) {
    let startX: CGFloat = 390
    let spacing: CGFloat = 31
    let colors: [NSColor] = [
        color(0xd6d1c7, alpha: 0.52),
        color(0xbab4aa, alpha: 0.62),
        color(0x908a81, alpha: 0.76),
        color(0x5d574f, alpha: 0.9),
        color(0x151515, alpha: 0.98),
    ]

    for (index, arrowColor) in colors.enumerated() {
        let x = startX + CGFloat(index) * spacing
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x - 8, y: centerY - 12))
        path.line(to: CGPoint(x: x + 6, y: centerY))
        path.line(to: CGPoint(x: x - 8, y: centerY + 12))
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        arrowColor.setStroke()
        path.stroke()
    }
}

func drawFooterIcon(in rect: CGRect) {
    guard let image = NSImage(contentsOf: iconURL) else { return }
    image.size = rect.size
    image.draw(in: rect)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidth,
    pixelsHigh: canvasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: .alphaFirst,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create background bitmap.")
}

bitmap.size = NSSize(width: canvasWidth, height: canvasHeight)
guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context.")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.shouldAntialias = true

let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
color(0xfbfbfa).setFill()
canvas.fill()

let contentRect = CGRect(x: 24, y: 82, width: 872, height: 464)
let contentPath = NSBezierPath(roundedRect: contentRect, xRadius: 12, yRadius: 12)
color(0xffffff, alpha: 0.94).setFill()
contentPath.fill()
color(0xdedbd4, alpha: 0.82).setStroke()
contentPath.lineWidth = 1
contentPath.stroke()

drawGrid(in: contentRect.insetBy(dx: 1, dy: 1))

let appIconRect = CGRect(x: 224, y: 262, width: 126, height: 126)
let applicationsRect = CGRect(x: 574, y: 258, width: 152, height: 124)
drawHavenIcon(in: appIconRect)
drawApplicationFolder(in: applicationsRect)
drawArrowTrail(centerY: 322)

drawText(
    "Haven",
    at: CGPoint(x: appIconRect.midX, y: 216),
    font: .systemFont(ofSize: 21, weight: .regular),
    color: .black
)
drawText(
    "Applications",
    at: CGPoint(x: applicationsRect.midX, y: 216),
    font: .systemFont(ofSize: 21, weight: .regular),
    color: .black
)

let footerRect = CGRect(x: 24, y: 36, width: 872, height: 72)
color(0xffffff, alpha: 0.92).setFill()
footerRect.fill()
color(0xdedbd4, alpha: 0.72).setStroke()
let divider = NSBezierPath()
divider.move(to: CGPoint(x: footerRect.minX, y: footerRect.maxY))
divider.line(to: CGPoint(x: footerRect.maxX, y: footerRect.maxY))
divider.lineWidth = 1
divider.stroke()

drawFooterIcon(in: CGRect(x: 46, y: 54, width: 34, height: 34))

let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
let footerTitle = NSAttributedString(
    string: "HAVEN",
    attributes: [.font: mono, .foregroundColor: color(0x151515)]
)
footerTitle.draw(at: CGPoint(x: 92, y: 72))

let footerSubtitle = NSAttributedString(
    string: "PRIVATE HOME LIBRARIES FOR MAC",
    attributes: [.font: mono, .foregroundColor: color(0x706a61)]
)
footerSubtitle.draw(at: CGPoint(x: 92, y: 54))

let rightParagraph = NSMutableParagraphStyle()
rightParagraph.alignment = .right
let rightAttributes: [NSAttributedString.Key: Any] = [
    .font: mono,
    .foregroundColor: color(0x151515),
    .paragraphStyle: rightParagraph,
]
NSString(string: "COPYRIGHT (C) 2026\nLOCAL-FIRST, OPEN SOURCE")
    .draw(in: CGRect(x: 636, y: 52, width: 230, height: 42), withAttributes: rightAttributes)

graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode background PNG.")
}

try data.write(to: outputURL, options: .atomic)
print(outputURL.path)
