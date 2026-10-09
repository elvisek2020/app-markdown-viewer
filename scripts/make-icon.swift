// Vygeneruje ikonu MDView (AppIcon.appiconset + PNG pro README) kreslením přes AppKit.
// Použití: swift scripts/make-icon.swift <výstupní adresář appiconset> [cesta k PNG 512 pro README]
//
// Motiv: list papíru se značkou Markdownu (M↓) na modrém podkladu a zelený odznak
// s kruhovými šipkami – „živý“ náhled, který se sám obnovuje.

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon() {
    // Podklad podle šablony macOS: zaoblený čtverec 824 × 824 se stínem.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x000000, 0.35)
    tileShadow.shadowBlurRadius = 28
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    tileShadow.set()
    color(0x1D4ED8).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [color(0x60A5FA), color(0x2563EB), color(0x1E3A8A)])!
        .draw(in: tile, angle: -60)
    // Jemný lesk v horní části.
    NSGradient(colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // List papíru s ohnutým rohem.
    let page = NSRect(x: 262, y: 196, width: 470, height: 610)
    let fold: CGFloat = 112
    let pagePath = NSBezierPath()
    pagePath.move(to: NSPoint(x: page.minX + 36, y: page.minY))
    pagePath.line(to: NSPoint(x: page.maxX - 36, y: page.minY))
    pagePath.curve(to: NSPoint(x: page.maxX, y: page.minY + 36),
                   controlPoint1: NSPoint(x: page.maxX - 16, y: page.minY),
                   controlPoint2: NSPoint(x: page.maxX, y: page.minY + 16))
    pagePath.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    pagePath.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    pagePath.line(to: NSPoint(x: page.minX + 36, y: page.maxY))
    pagePath.curve(to: NSPoint(x: page.minX, y: page.maxY - 36),
                   controlPoint1: NSPoint(x: page.minX + 16, y: page.maxY),
                   controlPoint2: NSPoint(x: page.minX, y: page.maxY - 16))
    pagePath.line(to: NSPoint(x: page.minX, y: page.minY + 36))
    pagePath.curve(to: NSPoint(x: page.minX + 36, y: page.minY),
                   controlPoint1: NSPoint(x: page.minX, y: page.minY + 16),
                   controlPoint2: NSPoint(x: page.minX + 16, y: page.minY))
    pagePath.close()

    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = color(0x0B1E5B, 0.45)
    pageShadow.shadowBlurRadius = 30
    pageShadow.shadowOffset = NSSize(width: 0, height: -14)
    pageShadow.set()
    color(0xFFFFFF).setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    pagePath.addClip()
    NSGradient(colors: [color(0xFFFFFF), color(0xE8EEF9)])!.draw(in: page, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Ohnutý roh.
    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    foldPath.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold + 18))
    foldPath.curve(to: NSPoint(x: page.maxX - fold + 18, y: page.maxY - fold),
                   controlPoint1: NSPoint(x: page.maxX - fold, y: page.maxY - fold + 8),
                   controlPoint2: NSPoint(x: page.maxX - fold + 8, y: page.maxY - fold))
    foldPath.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    foldPath.close()
    color(0xC7D2FE).setFill()
    foldPath.fill()

    // Značka Markdownu: „M“ a šipka dolů.
    let markColor = color(0x1E293B)
    let font = NSFont.systemFont(ofSize: 250, weight: .heavy)
    let mark = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: markColor])
    let markSize = mark.size()
    mark.draw(at: NSPoint(x: 300, y: 498 - markSize.height / 2 + 30))

    let arrow = NSBezierPath()
    let arrowX: CGFloat = 600
    arrow.move(to: NSPoint(x: arrowX - 26, y: 640))
    arrow.line(to: NSPoint(x: arrowX + 26, y: 640))
    arrow.line(to: NSPoint(x: arrowX + 26, y: 520))
    arrow.line(to: NSPoint(x: arrowX + 74, y: 520))
    arrow.line(to: NSPoint(x: arrowX, y: 430))
    arrow.line(to: NSPoint(x: arrowX - 74, y: 520))
    arrow.line(to: NSPoint(x: arrowX - 26, y: 520))
    arrow.close()
    markColor.setFill()
    arrow.fill()

    // Řádky textu pod značkou.
    color(0x94A3B8).setFill()
    for (index, width) in [330.0, 380.0, 250.0].enumerated() {
        let y = 360 - CGFloat(index) * 56
        NSBezierPath(roundedRect: NSRect(x: 312, y: y, width: width, height: 26), xRadius: 13, yRadius: 13).fill()
    }

    // Odznak „živý náhled“: zelený kruh s kruhovými šipkami.
    let badge = NSRect(x: 618, y: 166, width: 236, height: 236)
    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = color(0x052E16, 0.45)
    badgeShadow.shadowBlurRadius = 24
    badgeShadow.shadowOffset = NSSize(width: 0, height: -10)
    badgeShadow.set()
    color(0x16A34A).setFill()
    NSBezierPath(ovalIn: badge).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: badge).addClip()
    NSGradient(colors: [color(0x4ADE80), color(0x15803D)])!.draw(in: badge, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.9).setStroke()
    let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 6, dy: 6))
    ring.lineWidth = 10
    ring.stroke()

    drawRefreshArrows(center: NSPoint(x: badge.midX, y: badge.midY), radius: 58, lineWidth: 22)
}

/// Dvě kruhové šipky (obnovení) – kreslené ručně, SF Symbols ve skriptu bez bundlu nefungují.
func drawRefreshArrows(center: NSPoint, radius: CGFloat, lineWidth: CGFloat) {
    NSColor.white.setStroke()
    NSColor.white.setFill()
    for start: CGFloat in [35, 215] {
        let end = start + 110
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        arc.stroke()

        // Hrot ve směru otáčení (proti směru hodinových ručiček).
        let angle = end * .pi / 180
        let tip = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        let tangent = (x: -sin(angle), y: cos(angle))
        let normal = (x: cos(angle), y: sin(angle))
        let length = lineWidth * 1.5
        let width = lineWidth * 1.35
        let head = NSBezierPath()
        head.move(to: NSPoint(x: tip.x + tangent.x * length, y: tip.y + tangent.y * length))
        head.line(to: NSPoint(x: tip.x + normal.x * width, y: tip.y + normal.y * width))
        head.line(to: NSPoint(x: tip.x - normal.x * width, y: tip.y - normal.y * width))
        head.close()
        head.fill()
    }
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    // rep.size = 1024 bodů → kreslí se v souřadnicích 1024 × 1024 a bitmapa má požadovaný počet pixelů.
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("Použití: swift scripts/make-icon.swift <AppIcon.appiconset> [readme.png]")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))

if arguments.count >= 3 {
    try render(pixels: 512).write(to: URL(fileURLWithPath: arguments[2]))
}
print("Ikona vygenerována do \(output.path)")
