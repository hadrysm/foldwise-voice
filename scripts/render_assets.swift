// Renders the app icon set and the .dmg background image with AppKit.
// Run by scripts/build_swift_app.py:  swift scripts/render_assets.swift <outdir>
// Produces <outdir>/icon.iconset/*.png and <outdir>/dmg-background.png.

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

/// Draw into an exact pixel-sized bitmap (screen scale never leaks in).
func renderBitmap(pixelsWide: Int, pixelsHigh: Int,
                  draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw()
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func drawCentered(_ text: String, y: CGFloat, width: CGFloat,
                  font: NSFont, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attrs)
    (text as NSString).draw(at: NSPoint(x: (width - size.width) / 2, y: y),
                            withAttributes: attrs)
}

// MARK: - App icon on Apple's Big Sur grid: the tile fills 824/1024 of the

// canvas with a ~22.5% corner radius and a soft drop shadow, so it sits at
// the same visual weight as system app icons.

func drawIcon(size: CGFloat) {
    let inset = size * 100.0 / 1024.0
    let rect = NSRect(x: inset, y: inset,
                      width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.225
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current!.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.shadowBlurRadius = size * 0.02
    shadow.set()
    NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.22, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.current!.restoreGraphicsState()

    NSGradient(
        starting: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.22, alpha: 1),
        ending: NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.42, alpha: 1)
    )!.draw(in: tile, angle: 90)

    let emoji = "🎤" as NSString
    let attrs: [NSAttributedString.Key: Any] =
        [.font: NSFont.systemFont(ofSize: size * 0.5)]
    let textSize = emoji.size(withAttributes: attrs)
    emoji.draw(at: NSPoint(x: (size - textSize.width) / 2,
                           y: (size - textSize.height) / 2),
               withAttributes: attrs)
}

let iconsetDir = outDir.appendingPathComponent("icon.iconset")
try! FileManager.default.createDirectory(at: iconsetDir,
                                         withIntermediateDirectories: true)
let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in iconSizes {
    let rep = renderBitmap(pixelsWide: px, pixelsHigh: px) {
        drawIcon(size: CGFloat(px))
    }
    writePNG(rep, to: iconsetDir.appendingPathComponent(name))
}

// MARK: - DMG background: 660×400 pt (the conventional installer window size)

// drawn at 2x so Finder shows it sharp on retina. Icons render at 128 pt with
// centers at Finder (180, 190) and (480, 190); keep those areas clear.

let bgW: CGFloat = 660, bgH: CGFloat = 400

let bg = renderBitmap(pixelsWide: Int(bgW) * 2, pixelsHigh: Int(bgH) * 2) {
    NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)

    NSGradient(
        starting: NSColor(calibratedWhite: 0.925, alpha: 1),
        ending: NSColor(calibratedWhite: 0.975, alpha: 1)
    )!.draw(in: NSRect(x: 0, y: 0, width: bgW, height: bgH), angle: 90)

    // Arrow between the icon slots (icon centers at Finder y=190 → AppKit y=210).
    let arrowColor = NSColor(calibratedWhite: 0.62, alpha: 1)
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 268, y: 210))
    line.line(to: NSPoint(x: 368, y: 210))
    line.lineWidth = 6
    line.lineCapStyle = .round
    arrowColor.setStroke()
    line.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 366, y: 226))
    head.line(to: NSPoint(x: 392, y: 210))
    head.line(to: NSPoint(x: 366, y: 194))
    head.close()
    arrowColor.setFill()
    head.fill()

    // Gatekeeper walkthrough — this app is not notarized, so macOS blocks the
    // first launch and the user needs to know the way through.
    drawCentered("First launch: macOS will say it cannot verify the app. Click “Done”,",
                 y: 44, width: bgW,
                 font: NSFont.systemFont(ofSize: 11.5),
                 color: NSColor(calibratedWhite: 0.45, alpha: 1))
    drawCentered("then open System Settings → Privacy & Security and click “Open Anyway”.",
                 y: 27, width: bgW,
                 font: NSFont.systemFont(ofSize: 11.5),
                 color: NSColor(calibratedWhite: 0.45, alpha: 1))
}

bg.size = NSSize(width: bgW, height: bgH) // 144 dpi → Finder renders 660×400 pt
writePNG(bg, to: outDir.appendingPathComponent("dmg-background.png"))
