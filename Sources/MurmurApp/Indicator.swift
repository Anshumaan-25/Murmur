import AppKit
import MurmurCore

final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class IndicatorView: NSView {
    var message = "Listening"
    var amplitude: Double = 0
    var phase: CapturePhase = .idle
    var time: Double = 0
    var reduceMotion = false
    var dragOffset = NSPoint.zero
    private var bars = [Double](repeating: 0, count: 25)
    func step(level: Double, delta: Double) {
        amplitude = level; time += delta
        for i in bars.indices {
            let shape = 0.30 + 0.70 * pow(abs(sin(Double(i) * 0.72 + (reduceMotion ? 0 : time * 2.2))), 1.2)
            let target = phase == .listening ? level * shape : 0.06 + (reduceMotion ? 0 : 0.10 * (1 + sin(time * 3.4 - Double(i) * 0.26)))
            bars[i] += (target - bars[i]) * (1 - exp(-delta / 0.065))
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: frame, xRadius: 24, yRadius: 24)
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.20, alpha: 0.98), ending: Palette.background.withAlphaComponent(0.98))?.draw(in: path, angle: -60)
        Palette.violet.withAlphaComponent(0.26).setStroke(); path.lineWidth = 1; path.stroke()
        let accent = phase == .failed ? NSColor.systemOrange : (phase == .listening ? Palette.mint : Palette.violet)
        accent.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 14, width: 112, height: 50), xRadius: 14, yRadius: 14).fill()
        for i in bars.indices {
            let height = 3 + CGFloat(bars[i]) * 33
            accent.withAlphaComponent(0.55 + Double(i) / 60).setFill()
            NSBezierPath(roundedRect: NSRect(x: 23 + CGFloat(i) * 3.6, y: 39 - height / 2, width: 2, height: height), xRadius: 1, yRadius: 1).fill()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let font: NSFont = .systemFont(ofSize: 12, weight: .semibold)
        let isLong = message.count > 32
        if isLong { paragraph.lineBreakMode = .byWordWrapping }
        (message as NSString).draw(in: NSRect(x: 140, y: isLong ? 29 : 38, width: bounds.width - 157, height: isLong ? 33 : 18), withAttributes: [.font:font, .foregroundColor:Palette.text, .paragraphStyle:paragraph])
        let hint = phase == .listening ? "Speak naturally · Esc to cancel" : (phase == .processing ? "Transcribing on your Mac" : (message.hasPrefix("Copied") ? "Your text is on the clipboard" : "MURMUR · ON DEVICE"))
        (hint as NSString).draw(at: NSPoint(x: 140, y: 17), withAttributes: [.font:NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor:Palette.muted])
    }
    override func mouseDown(with event: NSEvent) { dragOffset = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) { let point = NSEvent.mouseLocation; window?.setFrameOrigin(NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)) }
    override func mouseUp(with event: NSEvent) {
        guard let window, let screen = window.screen else { return }
        let available = screen.visibleFrame; var frame = window.frame
        frame.origin.x = frame.midX < available.midX ? available.minX + 18 : available.maxX - frame.width - 18
        frame.origin.y = max(available.minY + 18, min(frame.origin.y, available.maxY - frame.height - 18))
        window.setFrame(frame, display: true); UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: "indicatorPosition")
    }
}
@MainActor final class Indicator {
    let panel: IndicatorPanel
    let content = IndicatorView()
    var inputLevel: (() -> Float)?
    private var dismissal: DispatchWorkItem?
    private var timer: Timer?
    private var meter = AudioMeter()
    private var tick = ProcessInfo.processInfo.systemUptime
    private var manualLevel: Float = 0
    var animating: Bool { timer != nil }
    private(set) var frameIntervals: [Double] = []
    init() {
        panel = IndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 376, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.contentView = content
        panel.setAccessibilityLabel("Murmur dictation status")
        if let screen = NSScreen.main {
            let available = screen.visibleFrame
            var origin = NSPoint(x: available.midX - 188, y: available.minY + 28)
            if let point = UserDefaults.standard.string(forKey: "indicatorPosition") { origin = NSPointFromString(point) }
            origin.x = max(available.minX + 12, min(origin.x, available.maxX - 388)); origin.y = max(available.minY + 12, min(origin.y, available.maxY - 90))
            panel.setFrameOrigin(origin)
        }
    }
    deinit { timer?.invalidate(); dismissal?.cancel() }
    func show(_ message: String, phase: CapturePhase) {
        dismissal?.cancel(); content.message = message; content.phase = phase; content.reduceMotion = Palette.reduceMotion
        content.setAccessibilityLabel(message); content.needsDisplay = true
        let wasHidden = !panel.isVisible
        panel.orderFrontRegardless()
        if wasHidden && !Palette.reduceMotion {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.16; panel.animator().alphaValue = 1 }
        } else { panel.alphaValue = 1 }
        if timer == nil {
            tick = ProcessInfo.processInfo.systemUptime; frameIntervals = []
            let timer = Timer(timeInterval: Palette.reduceMotion ? 1.0 / 20 : 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.002; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        panel.displayIfNeeded()
        if phase == .idle || phase == .cancelled || phase == .failed {
            let work = DispatchWorkItem { [weak self] in self?.hide() }; dismissal = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (phase == .failed || message.hasPrefix("Copied") ? 6 : 2), execute: work)
        }
    }
    private func refresh() {
        guard panel.isVisible else { timer?.invalidate(); timer = nil; return }
        let now = ProcessInfo.processInfo.systemUptime; let elapsed = now - tick; let delta = min(0.1, max(0.001, elapsed)); tick = now
        frameIntervals.append(elapsed); if frameIntervals.count > 180 { frameIntervals.removeFirst() }
        let rms = content.phase == .listening ? inputLevel?() ?? manualLevel : 0
        let level = meter.advance(rms: rms, delta: delta)
        content.step(level: level, delta: delta)
    }
    func hide() { dismissal?.cancel(); timer?.invalidate(); timer = nil; panel.orderOut(nil); meter = AudioMeter(); manualLevel = 0 }
    func level(_ value: Float) { manualLevel = value }
}
