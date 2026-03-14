#!/usr/bin/env swift

import AppKit

func generateIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let s = CGFloat(size)

    // Background - rounded rect with gradient
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.04, dy: s * 0.04),
                               xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(starting: NSColor(red: 0.38, green: 0.22, blue: 0.72, alpha: 1.0),
                              ending: NSColor(red: 0.58, green: 0.32, blue: 0.92, alpha: 1.0))!
    gradient.draw(in: bgPath, angle: -45)

    // Brain icon - simplified outline
    let cx = s * 0.5
    let cy = s * 0.48
    let r = s * 0.28

    NSColor.white.withAlphaComponent(0.95).setStroke()
    NSColor.white.withAlphaComponent(0.15).setFill()

    // Head outline (circle)
    let headPath = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r * 0.9, width: r * 2, height: r * 2.1))
    headPath.lineWidth = s * 0.03
    headPath.fill()
    headPath.stroke()

    // Brain folds - center line
    let centerLine = NSBezierPath()
    centerLine.move(to: NSPoint(x: cx, y: cy + r * 0.8))
    centerLine.line(to: NSPoint(x: cx, y: cy - r * 0.7))
    centerLine.lineWidth = s * 0.025
    centerLine.stroke()

    // Brain folds - left curves
    let leftCurve1 = NSBezierPath()
    leftCurve1.move(to: NSPoint(x: cx, y: cy + r * 0.4))
    leftCurve1.curve(to: NSPoint(x: cx - r * 0.6, y: cy + r * 0.1),
                     controlPoint1: NSPoint(x: cx - r * 0.4, y: cy + r * 0.5),
                     controlPoint2: NSPoint(x: cx - r * 0.7, y: cy + r * 0.3))
    leftCurve1.lineWidth = s * 0.02
    leftCurve1.stroke()

    let leftCurve2 = NSBezierPath()
    leftCurve2.move(to: NSPoint(x: cx, y: cy - r * 0.1))
    leftCurve2.curve(to: NSPoint(x: cx - r * 0.55, y: cy - r * 0.35),
                     controlPoint1: NSPoint(x: cx - r * 0.35, y: cy - r * 0.05),
                     controlPoint2: NSPoint(x: cx - r * 0.55, y: cy - r * 0.2))
    leftCurve2.lineWidth = s * 0.02
    leftCurve2.stroke()

    // Brain folds - right curves
    let rightCurve1 = NSBezierPath()
    rightCurve1.move(to: NSPoint(x: cx, y: cy + r * 0.4))
    rightCurve1.curve(to: NSPoint(x: cx + r * 0.6, y: cy + r * 0.1),
                      controlPoint1: NSPoint(x: cx + r * 0.4, y: cy + r * 0.5),
                      controlPoint2: NSPoint(x: cx + r * 0.7, y: cy + r * 0.3))
    rightCurve1.lineWidth = s * 0.02
    rightCurve1.stroke()

    let rightCurve2 = NSBezierPath()
    rightCurve2.move(to: NSPoint(x: cx, y: cy - r * 0.1))
    rightCurve2.curve(to: NSPoint(x: cx + r * 0.55, y: cy - r * 0.35),
                      controlPoint1: NSPoint(x: cx + r * 0.35, y: cy - r * 0.05),
                      controlPoint2: NSPoint(x: cx + r * 0.55, y: cy - r * 0.2))
    rightCurve2.lineWidth = s * 0.02
    rightCurve2.stroke()

    // Small sparkle dots
    NSColor.white.withAlphaComponent(0.9).setFill()
    let dotSize = s * 0.035

    // Top right sparkle
    let sparkle1 = NSBezierPath(ovalIn: NSRect(x: cx + r * 0.85, y: cy + r * 0.85, width: dotSize, height: dotSize))
    sparkle1.fill()

    let sparkle2 = NSBezierPath(ovalIn: NSRect(x: cx + r * 1.05, y: cy + r * 0.55, width: dotSize * 0.7, height: dotSize * 0.7))
    sparkle2.fill()

    let sparkle3 = NSBezierPath(ovalIn: NSRect(x: cx + r * 0.65, y: cy + r * 1.05, width: dotSize * 0.5, height: dotSize * 0.5))
    sparkle3.fill()

    // "P" text at bottom
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.13, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.7)
    ]
    let pText = NSAttributedString(string: "PILOT", attributes: attrs)
    let textSize = pText.size()
    pText.draw(at: NSPoint(x: cx - textSize.width / 2, y: s * 0.08))

    image.unlockFocus()
    return image
}

// Generate all sizes
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let basePath = "/Users/dongguk/Desktop/ObsidianPilot/ObsidianPilot/Assets.xcassets/AppIcon.appiconset"

for size in sizes {
    let image = generateIcon(size: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(size)x\(size)")
        continue
    }

    let filename = "icon_\(size)x\(size).png"
    let filePath = "\(basePath)/\(filename)"
    try! pngData.write(to: URL(fileURLWithPath: filePath))
    print("Generated \(filename)")
}

print("Done!")
