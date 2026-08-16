//
//  Generates DangerousDave2.iconset — pixel-art Dave in the EGA palette.
//  Run at build time; iconutil then packs the result into AppIcon.icns.
//

import Cocoa

// EGA palette subset, matching the game's own colours.
let ega: [Character: NSColor] = [
    "0": NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1),
    "1": NSColor(srgbRed: 0.00, green: 0.00, blue: 0.67, alpha: 1),
    "4": NSColor(srgbRed: 0.67, green: 0.00, blue: 0.00, alpha: 1),
    "9": NSColor(srgbRed: 0.33, green: 0.33, blue: 1.00, alpha: 1),
    "C": NSColor(srgbRed: 1.00, green: 0.33, blue: 0.33, alpha: 1),
    "E": NSColor(srgbRed: 1.00, green: 1.00, blue: 0.33, alpha: 1),
    "F": NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
]

// Dave: red cap, yellow EGA face, red shirt. 14x14 so it stays legible at 16px.
let dave = [
    "..............",
    ".....4444.....",
    "...44444444...",
    "..4444444444..",
    ".CCCCCCCCCCCC.",
    "...EEEEEEEE...",
    "...E0EEEE0E...",
    "...EEEEEEEE...",
    "....EE00EE....",
    "...EEEEEEEE...",
    "..4444444444..",
    ".444444444444.",
    "EE4444444444EE",
    "..4444444444.."
]

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let s = CGFloat(size)

    // Rounded "squircle" plate with the standard macOS margin.
    let inset = s * 0.055
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = plate.width * 0.2237
    let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    path.addClip()

    // Night-sky gradient, echoing the Museum Rooftops level.
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.28, alpha: 1),
        NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1)
    ])!
    gradient.draw(in: plate, angle: -90)

    // A few stars, deterministic so every rebuild is byte-identical.
    ega["F"]!.setFill()
    let starDot = max(1, s * 0.012)
    for i in 0..<14 {
        let sx = plate.minX + plate.width  * CGFloat((i &* 37) % 100) / 100.0
        let sy = plate.minY + plate.height * CGFloat((i &* 61) % 100) / 100.0
        if sy < plate.minY + plate.height * 0.45 { continue }   // keep stars up high
        NSBezierPath(rect: CGRect(x: sx, y: sy, width: starDot, height: starDot)).fill()
    }

    // Dave, centred, snapped to whole pixels so the art stays crisp.
    let cols = dave[0].count, rows = dave.count
    let cell = (s * 0.66 / CGFloat(cols)).rounded(.down)
    let artW = cell * CGFloat(cols), artH = cell * CGFloat(rows)
    let ox = ((s - artW) / 2).rounded(.down)
    let oy = ((s - artH) / 2).rounded(.down)

    for (r, line) in dave.enumerated() {
        for (c, ch) in line.enumerated() {
            guard let colour = ega[ch] else { continue }   // '.' is transparent
            colour.setFill()
            let rect = CGRect(
                x: ox + CGFloat(c) * cell,
                y: oy + CGFloat(rows - 1 - r) * cell,      // flip: AppKit origin is bottom-left
                width: cell, height: cell
            )
            NSBezierPath(rect: rect).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Sizes required for a complete .icns.
let variants: [(name: String, px: Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",     32),
    ("icon_32x32",      32), ("icon_32x32@2x",     64),
    ("icon_128x128",   128), ("icon_128x128@2x",  256),
    ("icon_256x256",   256), ("icon_256x256@2x",  512),
    ("icon_512x512",   512), ("icon_512x512@2x", 1024)
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DangerousDave2.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for v in variants {
    let rep = drawIcon(size: v.px)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(v.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(v.name).png"))
}
print("wrote \(variants.count) icon sizes to \(outDir)")
