import AppKit
import MurmurCore

final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class IndicatorView: NSView {
    var message = "Listening"
    var amplitude: Float = 0
    var phase: CapturePhase = .idle
    var dragOffset = NSPoint.zero
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.15, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 22, yRadius: 22).fill()
        let accent: NSColor = phase == .failed ? .systemOrange : NSColor(calibratedRed: 0.45, green: 0.92, blue: 0.75, alpha: 1)
        accent.setFill()
        for index in 0..<9 {
            let shape = Float(0.35 + 0.65 * abs(sin(Double(index) * 1.7)))
            let height = CGFloat(phase == .listening ? 4 + min(1, amplitude * 16) * shape * 30 : 7)
            let rectangle = NSRect(x: CGFloat(20 + index * 6), y: 34 - height / 2, width: 3, height: height)
            NSBezierPath(roundedRect: rectangle, xRadius: 1.5, yRadius: 1.5).fill()
        }
        let text = message as NSString
        text.draw(in: NSRect(x: 88, y: 19, width: bounds.width - 105, height: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
    }
    override func mouseDown(with event: NSEvent) { dragOffset = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) { let point = NSEvent.mouseLocation; window?.setFrameOrigin(NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)) }
    override func mouseUp(with event: NSEvent) {
        guard let window, let screen = window.screen else { return }
        let available = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = frame.midX < available.midX ? available.minX + 18 : available.maxX - frame.width - 18
        frame.origin.y = max(available.minY + 18, min(frame.origin.y, available.maxY - frame.height - 18))
        window.setFrame(frame, display: true)
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: "indicatorPosition")
    }
}
@MainActor final class Indicator {
    let panel: IndicatorPanel
    let content = IndicatorView()
    private var dismissal: DispatchWorkItem?
    init() {
        panel = IndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 68), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.contentView = content
        if let point = UserDefaults.standard.string(forKey: "indicatorPosition") { panel.setFrameOrigin(NSPointFromString(point)) }
        else if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 155, y: screen.visibleFrame.minY + 28)) }
    }
    func show(_ message: String, phase: CapturePhase) {
        dismissal?.cancel(); content.message = message; content.phase = phase; content.needsDisplay = true
        panel.orderFrontRegardless(); panel.displayIfNeeded()
        if phase == .idle || phase == .cancelled || phase == .failed {
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }; dismissal = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (phase == .failed ? 5 : 2), execute: work)
        }
    }
    func level(_ value: Float) { content.amplitude = value; content.needsDisplay = true }
}
