import AppKit
import MurmurCore

final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class IndicatorView: NSView {
    lazy var copyButton: NSButton = {
        let button = NSButton(title: "Copy Text", target: self, action: #selector(copyText))
        button.bezelStyle = .rounded
        button.refusesFirstResponder = true
        button.frame = NSRect(x: 286, y: 45, width: 80, height: 24)
        button.controlSize = .small
        button.isHidden = true
        addSubview(button)
        return button
    }()
    lazy var closeButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss notification")!,
                              target: self, action: #selector(closeNotice))
        button.isBordered = false
        button.refusesFirstResponder = true
        button.setAccessibilityLabel("Dismiss notification")
        button.toolTip = "Dismiss"
        button.frame = NSRect(x: 8, y: 46, width: 26, height: 26)
        button.isHidden = true
        addSubview(button)
        return button
    }()
    private var swipeDistance: CGFloat = 0
    var dismissNotice: (() -> Void)? {
        didSet { closeButton.isHidden = dismissNotice == nil; swipeDistance = 0 }
    }
    @objc private func closeNotice() { dismissNotice?() }

    override func scrollWheel(with event: NSEvent) {
        guard let dismissNotice, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else {
            super.scrollWheel(with: event)
            return
        }
        if event.phase.contains(.began) { swipeDistance = 0 }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swipeDistance = 0
            return
        }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            swipeDistance = 0
            return
        }
        let right = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        swipeDistance = max(0, swipeDistance + right)
        if swipeDistance >= 44 { dismissNotice() }
    }
    var copyResult: (() -> Void)? {
        didSet { copyButton.isHidden = copyResult == nil }
    }
    @objc private func copyText() { copyResult?() }
    var message = "Listening"
    var amplitude: Double = 0
    var phase: CapturePhase = .idle
    var time: Double = 0
    var reduceMotion = false
    var dragOffset = NSPoint.zero
    var didDock: ((NSRect, NSRect) -> Void)?
    var didDraw: (() -> Void)?
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
        didDraw?()
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: frame, xRadius: 24, yRadius: 24)
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.20, alpha: 0.98), ending: Palette.background.withAlphaComponent(0.98))?.draw(in: path, angle: -60)
        Palette.violet.withAlphaComponent(0.26).setStroke(); path.lineWidth = 1; path.stroke()
        let accent = phase == .failed ? NSColor.systemOrange : (phase == .listening ? Palette.mint : Palette.violet)
        if dismissNotice != nil {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let width = bounds.width - (copyResult == nil ? 56 : 141)
            (message as NSString).draw(in: NSRect(x: 42, y: 10, width: width, height: 50),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                 .foregroundColor: Palette.text, .paragraphStyle: paragraph])
            return
        }
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
        let hint = phase == .listening ? "Speak naturally · Esc to cancel" : (phase == .processing ? "Transcribing on your Mac" : (message.hasPrefix("Copied") ? "Your text is on the clipboard" : "KEYDOWN · ON DEVICE"))
        if copyResult == nil {
            (hint as NSString).draw(at: NSPoint(x: 140, y: 17), withAttributes: [.font:NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor:Palette.muted])
        }
    }
    override func mouseDown(with event: NSEvent) { dragOffset = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) { let point = NSEvent.mouseLocation; window?.setFrameOrigin(NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)) }
    override func mouseUp(with event: NSEvent) {
        guard let window, let screen = window.screen else { return }
        let available = screen.visibleFrame; var frame = window.frame
        frame.origin.x = frame.midX < available.midX ? available.minX + 18 : available.maxX - frame.width - 18
        frame.origin.y = max(available.minY + 18, min(frame.origin.y, available.maxY - frame.height - 18))
        window.setFrame(frame, display: true); didDock?(frame, available)
    }
}
@MainActor final class Indicator {
    private(set) var panel: IndicatorPanel
    let content = IndicatorView()
    var inputLevel: (() -> Float)?
    private var dismissal: DispatchWorkItem?
    private var timer: Timer?
    private var meter = AudioMeter()
    private var tick = ProcessInfo.processInfo.systemUptime
    private var manualLevel: Float = 0
    private var generation = UUID()
    private var announcedPhase: CapturePhase?
    private var wantsPresentation = false
    private var rebuildOnNextShow = false
    private var lastPresentation = 0.0
    private let defaults: UserDefaults?
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObserver: NSObjectProtocol?
    private let workspaceNotifications: NotificationCenter
    private let reducedMotion: @MainActor () -> Bool
    var preferredPoint: NSPoint?
    var didDraw: (() -> Void)?
    var animating: Bool { timer?.isValid == true }
    private(set) var frameIntervals: [Double] = []
    init(defaults: UserDefaults? = .standard,
         workspaceNotifications: NotificationCenter? = nil,
         reducedMotion: @escaping @MainActor () -> Bool = { Palette.reduceMotion }) {
        self.defaults = defaults
        self.workspaceNotifications = workspaceNotifications ?? NSWorkspace.shared.notificationCenter
        self.reducedMotion = reducedMotion
        panel = Self.makePanel(content: content)
        content.didDraw = { [weak self] in self?.didDraw?() }
        content.didDock = { [weak self] frame, visible in
            let area = visible.insetBy(dx: 12, dy: 12)
            self?.defaults?.set([Double((frame.minX - area.minX) / max(1, area.width - frame.width)),
                                Double((frame.minY - area.minY) / max(1, area.height - frame.height))], forKey: "indicatorDock")
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsPresentation else { return }
                self.present()
            }
        })
        accessibilityObserver = self.workspaceNotifications.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAnimation() }
        }
        place()
    }

    private static func makePanel(content: IndicatorView) -> IndicatorPanel {
        let panel = IndicatorPanel(contentRect: NSRect(x: 0, y: 0, width: 376, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        // The indicator belongs to a background app and must join other apps' fullscreen Spaces.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = content
        panel.setAccessibilityLabel("Keydown dictation status")
        return panel
    }

    deinit {
        timer?.invalidate()
        dismissal?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let accessibilityObserver { workspaceNotifications.removeObserver(accessibilityObserver) }
    }
    private func place() {
        let point = preferredPoint ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        var anchor = CGPoint(x: 1, y: 1)
        if let dock = defaults?.array(forKey: "indicatorDock") as? [Double], dock.count == 2 {
            anchor = CGPoint(x: dock[0], y: dock[1])
        } else if let legacy = defaults?.string(forKey: "indicatorPosition") {
            let old = NSPointFromString(legacy), area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            anchor = CGPoint(x: (old.x - area.minX) / max(1, area.width - 376), y: (old.y - area.minY) / max(1, area.height - 78))
        }
        panel.setFrame(IndicatorLayout.frame(in: screen.visibleFrame, size: CGSize(width: 376, height: 78), anchor: anchor), display: true)
    }
    func prepareAfterWake() {
        hide()
        preferredPoint = nil
        rebuildOnNextShow = true
    }

    private func present() {
        lastPresentation = ProcessInfo.processInfo.systemUptime
        place()
        panel.level = .statusBar
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    func preview(reset: Bool = false) {
        if reset { defaults?.removeObject(forKey: "indicatorDock"); defaults?.removeObject(forKey: "indicatorPosition") }
        preferredPoint = nil; show("Recording indicator preview", phase: .idle)
    }
    var diagnostic: [String: Any] {
        ["visible": panel.isVisible, "alpha": panel.alphaValue, "level": panel.level.rawValue,
         "frame": NSStringFromRect(panel.frame), "on_display": NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) },
         "animating": animating, "on_active_space": panel.isOnActiveSpace, "occlusion_visible": panel.occlusionState.contains(.visible)]
    }
    func show(_ message: String, phase: CapturePhase, copyResult: (() -> Void)? = nil, duration: Double = 2) {
        generation = UUID()
        if rebuildOnNextShow {
            // AppKit can still report draws for a panel the Window Server lost during sleep.
            panel.contentView = nil
            panel = Self.makePanel(content: content)
            rebuildOnNextShow = false
        }
        wantsPresentation = true
        if announcedPhase != phase {
            announcedPhase = phase
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        dismissal?.cancel(); content.message = message; content.phase = phase
        content.dismissNotice = [.idle, .cancelled, .failed].contains(phase) ? { [weak self] in self?.hide() } : nil
        content.copyResult = copyResult
        content.setAccessibilityLabel(message); content.needsDisplay = true
        present()
        updateAnimation()
        if phase == .idle || phase == .cancelled || phase == .failed {
            let current = generation
            let work = DispatchWorkItem { [weak self] in
                guard self?.generation == current else { return }; self?.hide()
            }; dismissal = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }
    private func updateAnimation() {
        guard wantsPresentation else { return }
        content.reduceMotion = reducedMotion()
        let interval = content.reduceMotion ? 1.0 / 20 : 1.0 / 60
        if (content.reduceMotion && content.phase != .listening) || [.idle, .cancelled, .failed].contains(content.phase) {
            timer?.invalidate()
            timer = nil
            content.step(level: 0, delta: 1)
            return
        }
        content.needsDisplay = true
        guard timer?.isValid != true || timer?.timeInterval != interval else { return }
        timer?.invalidate()
        tick = ProcessInfo.processInfo.systemUptime
        frameIntervals = []
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.002
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refresh() {
        guard wantsPresentation else { return }
        let now = ProcessInfo.processInfo.systemUptime; let elapsed = now - tick; let delta = min(0.1, max(0.001, elapsed)); tick = now
        if (content.phase == .starting || content.phase == .listening), now - lastPresentation >= 0.25,
           !panel.isVisible || !panel.isOnActiveSpace || !panel.occlusionState.contains(.visible) {
            present()
        }
        frameIntervals.append(elapsed); if frameIntervals.count > 180 { frameIntervals.removeFirst() }
        let rms = content.phase == .listening ? inputLevel?() ?? manualLevel : 0
        let level = meter.advance(rms: rms, delta: delta)
        content.step(level: level, delta: delta)
    }
    func hide() {
        wantsPresentation = false
        generation = UUID()
        dismissal?.cancel()
        dismissal = nil
        timer?.invalidate()
        timer = nil
        content.dismissNotice = nil
        content.copyResult = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
        meter = AudioMeter()
        manualLevel = 0
        announcedPhase = nil
    }
    func level(_ value: Float) { manualLevel = value }
}
