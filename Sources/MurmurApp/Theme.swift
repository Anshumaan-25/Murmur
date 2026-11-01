import AppKit
import QuartzCore

enum Palette {
    static let background = NSColor(srgbRed: 0.045, green: 0.052, blue: 0.085, alpha: 1)
    static let surface = NSColor(srgbRed: 0.077, green: 0.087, blue: 0.13, alpha: 1)
    static let raised = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.18, alpha: 1)
    static let text = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.98, alpha: 1)
    static let muted = NSColor(srgbRed: 0.58, green: 0.62, blue: 0.73, alpha: 1)
    static let violet = NSColor(srgbRed: 0.66, green: 0.58, blue: 1, alpha: 1)
    static let mint = NSColor(srgbRed: 0.48, green: 0.91, blue: 0.78, alpha: 1)
    static let line = NSColor.white.withAlphaComponent(0.075)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .medium))?.tinted(color)
    }
}
private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let copy = self.copy() as! NSImage; copy.isTemplate = false
        copy.lockFocus(); color.set(); NSRect(origin: .zero, size: size).fill(using: .sourceAtop); copy.unlockFocus(); return copy
    }
}
final class CanvasView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill(); bounds.fill()
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: bounds).addClip()
        NSGradient(starting: Palette.violet.withAlphaComponent(0.10), ending: .clear)?.draw(fromCenter: NSPoint(x: bounds.width * 0.90, y: bounds.height), radius: 0, toCenter: NSPoint(x: bounds.width * 0.90, y: bounds.height), radius: bounds.width * 0.7, options: [.drawsBeforeStartingLocation])
        NSGraphicsContext.restoreGraphicsState()
    }
}
final class SurfaceView: NSView {
    var color = Palette.surface
    var radius: CGFloat = 18
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        color.setFill(); path.fill(); Palette.line.setStroke(); path.lineWidth = 1; path.stroke()
    }
}
final class BrandMark: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 36) }
    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        NSGradient(starting: Palette.violet, ending: NSColor(srgbRed: 0.42, green: 0.32, blue: 0.86, alpha: 1))?.draw(in: NSBezierPath(roundedRect: frame, xRadius: 11, yRadius: 11), angle: -45)
        NSColor.white.setFill()
        for (index, height) in [10.0, 20, 14, 24, 10].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: frame.midX - 12 + CGFloat(index) * 5.5, y: frame.midY - height / 2, width: 2.6, height: height), xRadius: 1.3, yRadius: 1.3).fill()
        }
    }
}
final class WaveArtwork: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20).addClip()
        NSGradient(starting: Palette.violet.withAlphaComponent(0.13), ending: Palette.mint.withAlphaComponent(0.02))?.draw(in: bounds, angle: -25)
        for line in 0..<13 {
            let path = NSBezierPath()
            for step in 0...120 {
                let x = bounds.width * (0.43 + 0.57 * CGFloat(step) / 120)
                let envelope = exp(-pow((Double(step) / 120 - 0.63) * 3.4, 2))
                let y = bounds.height * 0.48 + CGFloat(sin(Double(step) * 0.076 + Double(line) * 0.15) * envelope * 49) + CGFloat(line - 6) * 5
                if step == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
            }
            (line < 6 ? Palette.violet : Palette.mint).withAlphaComponent(0.13 + Double(line % 4) * 0.045).setStroke(); path.lineWidth = 1; path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
final class SidebarButton: NSButton {
    var chosen = false { didSet { needsDisplay = true } }
    var icon = "waveform"
    var perform: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(_ title: String, icon: String, action: @escaping () -> Void) {
        super.init(frame: .zero); self.title = title; self.icon = icon; perform = action
        target = self; self.action = #selector(invoke); isBordered = false; setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 44) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self); addTrackingArea(tracking!) }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        (chosen ? Palette.violet.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(hovered ? 0.045 : 0)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 10, yRadius: 10).fill()
        if chosen { Palette.violet.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 13, width: 3, height: 18), xRadius: 1.5, yRadius: 1.5).fill() }
        let tint = chosen ? Palette.violet : Palette.muted
        Palette.symbol(icon, size: 16, color: tint)?.draw(in: NSRect(x: 15, y: 14, width: 17, height: 17))
        (title as NSString).draw(at: NSPoint(x: 44, y: 14), withAttributes: [.font:NSFont.systemFont(ofSize: 13, weight: chosen ? .semibold : .medium), .foregroundColor:chosen ? Palette.text : Palette.muted])
    }
    @objc private func invoke() { perform?() }
}
