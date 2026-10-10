// Pozadí okna DMG: modrý přechod (ladí s ikonou), šipka od aplikace ke složce Aplikace a pokyn.
//   swift scripts/dmg-background.swift <výstup.png> <měřítko 1|2>
// Tón je střední světlosti: popisky ikon kreslí Finder černě (světlý vzhled) i bíle (tmavý)
// a oboje má na tomhle pozadí kontrast kolem 4,5 : 1.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write("Použití: dmg-background.swift <výstup.png> <měřítko>\n".data(using: .utf8)!)
    exit(1)
}

// Rozměry v bodech; musí sedět s window_rect a icon_locations v scripts/dmg-settings.py.
let size = CGSize(width: 600, height: 420)
let iconY: CGFloat = 190          // střed ikon od horního okraje
let leftX: CGFloat = 150
let rightX: CGFloat = 450

let width = Int(size.width * scale)
let height = Int(size.height * scale)
let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.scaleBy(x: scale, y: scale)
// Souřadnice shora dolů jako ve Finderu.
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

// Přechod shora dolů.
let gradient = CGGradient(colorsSpace: nil, colors: [color(0x5C88C2), color(0x4A6AA3)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

// Šipka mezi ikonami (ikony mají 128 bodů, mezera kolem nich 24).
let start = leftX + 64 + 28
let end = rightX - 64 - 28
let shaft: CGFloat = 10
let headLength: CGFloat = 26
let headWidth: CGFloat = 34
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: start, y: iconY - shaft / 2))
arrow.addLine(to: CGPoint(x: end - headLength, y: iconY - shaft / 2))
arrow.addLine(to: CGPoint(x: end - headLength, y: iconY - headWidth / 2))
arrow.addLine(to: CGPoint(x: end, y: iconY))
arrow.addLine(to: CGPoint(x: end - headLength, y: iconY + headWidth / 2))
arrow.addLine(to: CGPoint(x: end - headLength, y: iconY + shaft / 2))
arrow.addLine(to: CGPoint(x: start, y: iconY + shaft / 2))
arrow.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: color(0x1B2A4A, 0.35))
context.setLineJoin(.round)
context.setLineWidth(4)
context.setStrokeColor(color(0xFFFFFF, 0.92))
context.setFillColor(color(0xFFFFFF, 0.92))
context.addPath(arrow)
context.drawPath(using: .fillStroke)
context.restoreGState()

// Pokyn pod ikonami (text kreslí AppKit – kontext je převrácený, proto přes NSGraphicsContext).
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let shadow = NSShadow()
shadow.shadowColor = NSColor(cgColor: color(0x1B2A4A, 0.4))
shadow.shadowOffset = NSSize(width: 0, height: -1)
shadow.shadowBlurRadius = 3
let text = NSAttributedString(string: "Přetáhni MDView do složky Aplikace", attributes: [
    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .shadow: shadow,
])
text.draw(in: CGRect(x: 0, y: 318, width: size.width, height: 24))
NSGraphicsContext.current = nil

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
rep.size = size
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[1]))
