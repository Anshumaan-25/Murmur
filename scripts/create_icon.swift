import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64), ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256), ("icon_256x256@2x",512), ("icon_512x512",512), ("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024; let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let path = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 196, yRadius: 196)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.30); shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -18)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor(srgbRed: 0.48, green: 0.37, blue: 0.86, alpha: 1).setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.72, green: 0.65, blue: 1, alpha: 1), ending: NSColor(srgbRed: 0.39, green: 0.28, blue: 0.79, alpha: 1))!.draw(in: path, angle: -65)
    NSColor.white.withAlphaComponent(0.25).setStroke(); path.lineWidth = 3; path.stroke()
    for (i, height) in [190.0, 390, 270, 470, 190].enumerated() {
        let bar = NSBezierPath(roundedRect: NSRect(x: 282 + Double(i) * 101, y: 512 - height / 2, width: 53, height: height), xRadius: 26.5, yRadius: 26.5)
        NSColor.white.withAlphaComponent(i == 4 ? 0.85 : 1).setFill(); bar.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
