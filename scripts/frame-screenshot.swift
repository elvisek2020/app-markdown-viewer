// Zasadí snímek náhledu do okna ve stylu macOS (titulek, semafor, stín) – obrázky do README.
// Použití: swift scripts/frame-screenshot.swift <vstup.png> <výstup.png> <titulek> [light|dark]

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 4, let screenshot = NSImage(contentsOfFile: arguments[1]),
      let screenshotRep = screenshot.representations.first else {
    print("Použití: swift scripts/frame-screenshot.swift <vstup.png> <výstup.png> <titulek> [light|dark]")
    exit(1)
}
let dark = arguments.count >= 5 && arguments[4] == "dark"
let scale: CGFloat = 2
let contentWidth = CGFloat(screenshotRep.pixelsWide)
let contentHeight = CGFloat(screenshotRep.pixelsHigh)
let titleBar = 52 * scale
let margin = 48 * scale
let radius = 12 * scale
let width = contentWidth + 2 * margin
let height = contentHeight + titleBar + 2 * margin

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let window = NSRect(x: margin, y: margin, width: contentWidth, height: contentHeight + titleBar)
let windowPath = NSBezierPath(roundedRect: window, xRadius: radius, yRadius: radius)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.6 : 0.3)
shadow.shadowBlurRadius = 30 * scale
shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
shadow.set()
(dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
windowPath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
windowPath.addClip()
// Titulkový pruh.
(dark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
NSRect(x: window.minX, y: window.maxY - titleBar, width: window.width, height: titleBar).fill()
(dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.82, alpha: 1)).setFill()
NSRect(x: window.minX, y: window.maxY - titleBar, width: window.width, height: scale).fill()
// Obsah.
screenshot.draw(in: NSRect(x: window.minX, y: window.minY, width: contentWidth, height: contentHeight))
NSGraphicsContext.restoreGraphicsState()

// Semafor.
for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    let color = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    color.setFill()
    let diameter = 12 * scale
    NSBezierPath(ovalIn: NSRect(
        x: window.minX + 20 * scale + CGFloat(index) * 20 * scale,
        y: window.maxY - titleBar / 2 - diameter / 2,
        width: diameter, height: diameter
    )).fill()
}

// Titulek.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let title = NSAttributedString(string: arguments[3], attributes: [
    .font: NSFont.systemFont(ofSize: 13 * scale, weight: .semibold),
    .foregroundColor: dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1),
    .paragraphStyle: paragraph,
])
let titleHeight = title.size().height
title.draw(in: NSRect(x: window.minX, y: window.maxY - titleBar / 2 - titleHeight / 2, width: window.width, height: titleHeight))

(dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).setStroke()
windowPath.lineWidth = scale
windowPath.stroke()

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("Uloženo: \(arguments[2])")
