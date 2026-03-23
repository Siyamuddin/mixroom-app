import AppKit
import Foundation

struct Config {
    let sourceIconPath: String
    let outputPngPath: String
    let canvasSize: CGFloat
}

func parseConfig() -> Config? {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        fputs("Usage: generate_document_icon.swift <source-icon> <output-png> [size]\n", stderr)
        return nil
    }

    let size = args.count >= 4 ? CGFloat(Double(args[3]) ?? 1024.0) : 1024.0
    return Config(
        sourceIconPath: args[1],
        outputPngPath: args[2],
        canvasSize: max(256.0, size)
    )
}

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawShadow(blur: CGFloat, offset: NSSize, color: NSColor, _ block: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.shadowColor = color
    shadow.set()
    block()
    NSGraphicsContext.restoreGraphicsState()
}

guard let config = parseConfig() else {
    exit(1)
}

let sourceUrl = URL(fileURLWithPath: config.sourceIconPath)
guard let appIcon = NSImage(contentsOf: sourceUrl) else {
    fputs("Failed to load source icon at \(config.sourceIconPath)\n", stderr)
    exit(1)
}

let size = config.canvasSize
let canvas = NSSize(width: size, height: size)
let outputImage = NSImage(size: canvas)

outputImage.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Failed to acquire drawing context\n", stderr)
    outputImage.unlockFocus()
    exit(1)
}

context.setAllowsAntialiasing(true)
NSGraphicsContext.current?.imageInterpolation = .high

let pageRect = NSRect(
    x: size * 0.14,
    y: size * 0.08,
    width: size * 0.72,
    height: size * 0.84
)
let pageRadius = size * 0.09
let foldSize = size * 0.18

drawShadow(
    blur: size * 0.035,
    offset: NSSize(width: 0, height: -size * 0.015),
    color: NSColor(calibratedWhite: 0.0, alpha: 0.18)
) {
    NSColor.white.setFill()
    roundedPath(pageRect, radius: pageRadius).fill()
}

let pagePath = roundedPath(pageRect, radius: pageRadius)
pagePath.addClip()
NSGradient(
    colorsAndLocations:
        (NSColor(calibratedRed: 0.995, green: 0.997, blue: 1.0, alpha: 1.0), 0.0),
        (NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.99, alpha: 1.0), 0.55),
        (NSColor(calibratedRed: 0.935, green: 0.95, blue: 0.975, alpha: 1.0), 1.0)
)?.draw(in: pagePath, angle: -90)

let foldOrigin = NSPoint(x: pageRect.maxX - foldSize, y: pageRect.maxY - foldSize)
let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: pageRect.maxX - foldSize, y: pageRect.maxY))
foldPath.line(to: NSPoint(x: pageRect.maxX, y: pageRect.maxY))
foldPath.line(to: NSPoint(x: pageRect.maxX, y: pageRect.maxY - foldSize))
foldPath.close()

NSGradient(
    colorsAndLocations:
        (NSColor(calibratedRed: 0.9, green: 0.94, blue: 0.985, alpha: 1.0), 0.0),
        (NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.96, alpha: 1.0), 1.0)
)?.draw(in: foldPath, angle: -45)

NSColor(calibratedRed: 0.75, green: 0.82, blue: 0.91, alpha: 0.7).setStroke()
foldPath.lineWidth = size * 0.008
foldPath.stroke()

let foldShadow = NSBezierPath()
foldShadow.move(to: NSPoint(x: foldOrigin.x, y: pageRect.maxY))
foldShadow.line(to: NSPoint(x: foldOrigin.x, y: foldOrigin.y))
foldShadow.line(to: NSPoint(x: pageRect.maxX, y: foldOrigin.y))
NSColor(calibratedWhite: 0.0, alpha: 0.08).setStroke()
foldShadow.lineWidth = size * 0.01
foldShadow.stroke()

NSColor(calibratedRed: 0.8, green: 0.86, blue: 0.93, alpha: 1.0).setStroke()
pagePath.lineWidth = size * 0.01
pagePath.stroke()

let lineColor = NSColor(calibratedRed: 0.86, green: 0.9, blue: 0.95, alpha: 0.85)
for index in 0..<3 {
    let y = pageRect.minY + size * (0.17 + CGFloat(index) * 0.07)
    let lineRect = NSRect(
        x: pageRect.minX + size * 0.11,
        y: y,
        width: pageRect.width - size * 0.22,
        height: size * 0.018
    )
    let linePath = roundedPath(lineRect, radius: size * 0.009)
    lineColor.setFill()
    linePath.fill()
}

let badgeSize = size * 0.42
let badgeRect = NSRect(
    x: (size - badgeSize) / 2.0,
    y: pageRect.midY - badgeSize * 0.1,
    width: badgeSize,
    height: badgeSize
)
let badgePath = roundedPath(badgeRect, radius: badgeSize * 0.24)

drawShadow(
    blur: size * 0.03,
    offset: NSSize(width: 0, height: -size * 0.012),
    color: NSColor(calibratedRed: 0.05, green: 0.14, blue: 0.28, alpha: 0.22)
) {
    badgePath.addClip()
    NSGradient(
        colorsAndLocations:
            (NSColor(calibratedRed: 0.14, green: 0.22, blue: 0.42, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.2, green: 0.52, blue: 0.88, alpha: 1.0), 0.52),
            (NSColor(calibratedRed: 0.13, green: 0.78, blue: 0.78, alpha: 1.0), 1.0)
    )?.draw(in: badgePath, angle: -55)
}

let badgeStrokePath = roundedPath(badgeRect, radius: badgeSize * 0.24)
NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
badgeStrokePath.lineWidth = size * 0.008
badgeStrokePath.stroke()

let highlightRect = NSRect(
    x: badgeRect.minX + badgeSize * 0.1,
    y: badgeRect.minY + badgeSize * 0.58,
    width: badgeSize * 0.8,
    height: badgeSize * 0.22
)
let highlightPath = roundedPath(highlightRect, radius: badgeSize * 0.11)
highlightPath.addClip()
NSGradient(
    colorsAndLocations:
        (NSColor(calibratedWhite: 1.0, alpha: 0.26), 0.0),
        (NSColor(calibratedWhite: 1.0, alpha: 0.0), 1.0)
)?.draw(in: highlightPath, angle: -90)

let appIconInset = badgeSize * 0.17
let appIconRect = badgeRect.insetBy(dx: appIconInset, dy: appIconInset)
appIcon.draw(
    in: appIconRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)

let label = ".mixroom" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let labelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.048, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.29, green: 0.36, blue: 0.47, alpha: 0.92),
    .paragraphStyle: paragraph,
]
let labelRect = NSRect(
    x: pageRect.minX + size * 0.08,
    y: pageRect.minY + size * 0.06,
    width: pageRect.width - size * 0.16,
    height: size * 0.08
)
label.draw(in: labelRect, withAttributes: labelAttributes)

outputImage.unlockFocus()

guard
    let tiff = outputImage.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode output PNG\n", stderr)
    exit(1)
}

let outputUrl = URL(fileURLWithPath: config.outputPngPath)
try FileManager.default.createDirectory(
    at: outputUrl.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
do {
    try pngData.write(to: outputUrl)
} catch {
    fputs("Failed to write PNG to \(config.outputPngPath): \(error)\n", stderr)
    exit(1)
}
