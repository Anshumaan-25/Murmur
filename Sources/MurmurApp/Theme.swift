import AppKit
import QuartzCore

enum Palette {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static let background = adaptive(rgb(0.94, 0.95, 0.98), rgb(0.045, 0.052, 0.085))
    static let surface = adaptive(rgb(0.99, 0.99, 1), rgb(0.077, 0.087, 0.13))
    static let raised = adaptive(rgb(0.89, 0.91, 0.96), rgb(0.11, 0.12, 0.18))
    static let text = NSColor.labelColor
    static let muted = NSColor.secondaryLabelColor
    static let violet = adaptive(rgb(0.33, 0.21, 0.74), rgb(0.66, 0.58, 1))
    static let mint = adaptive(rgb(0.04, 0.36, 0.29), rgb(0.48, 0.91, 0.78))
    static let line = adaptive(NSColor.black.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0.12))
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
    var chosen = false {
        didSet {
            state = chosen ? .on : .off
            if chosen != oldValue { NSAccessibility.post(element: self, notification: .valueChanged) }
            needsDisplay = true
        }
    }
    var moveSelection: ((Int) -> Void)?
    var icon = "waveform"
    var perform: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    init(_ title: String, icon: String, action: @escaping () -> Void) {
        super.init(frame: .zero); self.title = title; self.icon = icon; perform = action
        target = self; self.action = #selector(invoke); isBordered = false
        setButtonType(.radio)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }
    override var intrinsicContentSize: NSSize { NSSize(width: 152, height: 44) }
    override func updateTrackingAreas() { super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }; tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self); addTrackingArea(tracking!) }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        (chosen ? Palette.violet.withAlphaComponent(0.14) : Palette.text.withAlphaComponent(hovered ? 0.045 : 0)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 10, yRadius: 10).fill()
        if chosen { Palette.violet.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 13, width: 3, height: 18), xRadius: 1.5, yRadius: 1.5).fill() }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
            ring.lineWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 3 : 2
            ring.stroke()
        }
        let tint = chosen ? Palette.violet : Palette.muted
        Palette.symbol(icon, size: 16, color: tint)?.draw(in: NSRect(x: 15, y: 14, width: 17, height: 17))
        (title as NSString).draw(at: NSPoint(x: 44, y: 14), withAttributes: [.font:NSFont.systemFont(ofSize: 13, weight: chosen ? .semibold : .medium), .foregroundColor:chosen ? Palette.text : Palette.muted])
    }
    override func accessibilityValue() -> Any? { NSNumber(value: chosen ? 1 : 0) }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            if event.keyCode == 125 { moveSelection?(1); return }
            if event.keyCode == 126 { moveSelection?(-1); return }
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    @objc private func invoke() { if isEnabled { perform?() } }
}

final class WorkspaceScrollView: NSScrollView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = Palette.line.cgColor
        }
    }
}
