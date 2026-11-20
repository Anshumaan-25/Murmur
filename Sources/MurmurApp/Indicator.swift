import AppKit
import MurmurCore

final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
enum IndicatorNotice {
    case status, inserted, unconfirmed, attention
}

final class IndicatorView: NSView {
    private let headline = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let check = NSImageView()
    private let meterFrame = NSRect(x: 15, y: 3, width: 57, height: 36)
    private var showsMeter = false
    private(set) var preferredSize = NSSize(width: 150, height: 38)

    override init(frame: NSRect) {
        super.init(frame: frame)
        headline.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        check.contentTintColor = Palette.mint
        check.setAccessibilityElement(false)
        for view in [headline, detail, check] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("Unsupported initializer") }

    lazy var copyButton: NSButton = {
        let button = NSButton(title: "Copy Text", target: self, action: #selector(copyText))
        button.bezelStyle = .rounded
        button.refusesFirstResponder = true
        button.toolTip = "Copy Text"
        button.setAccessibilityLabel("Copy Text")
        button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
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
        button.contentTintColor = .secondaryLabelColor
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
    func configure(message: String, notice: IndicatorNotice) {
        let isCard = notice == .unconfirmed || notice == .attention
        let inserted = notice == .inserted
        showsMeter = dismissNotice == nil && !isCard
        check.isHidden = !inserted
        detail.isHidden = !isCard
        copyButton.imagePosition = inserted ? .imageOnly : .noImage
        copyButton.isBordered = !inserted
        copyButton.contentTintColor = inserted ? .secondaryLabelColor : nil

        if isCard {
            let prefix = "Text ready — "
            if notice == .unconfirmed {
                headline.stringValue = "Check the text field"
                detail.stringValue = "Keydown couldn’t verify insertion."
            } else if message.hasPrefix(prefix) {
                headline.stringValue = "Text ready"
                let explanation = message.dropFirst(prefix.count)
                detail.stringValue = explanation.prefix(1).uppercased() + explanation.dropFirst()
            } else {
                headline.stringValue = phase == .failed ? "Dictation needs attention" : "Check dictation"
                detail.stringValue = message
            }
            let width: CGFloat = 334
            let bodyWidth = width - 52
            let measured = detail.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: bodyWidth, height: 1000)).height ?? 16
            let bodyHeight = max(17, ceil(measured))
            let height = 49 + bodyHeight
            preferredSize = NSSize(width: width, height: height)
            closeButton.frame = NSRect(x: 6, y: height - 33, width: 26, height: 26)
            let titleRight = copyResult == nil ? width - 14 : width - 97
            headline.frame = NSRect(x: 36, y: height - 30, width: titleRight - 36, height: 19)
            detail.frame = NSRect(x: 36, y: 12, width: bodyWidth, height: bodyHeight)
            copyButton.frame = NSRect(x: width - 91, y: height - 33, width: 80, height: 25)
        } else {
            headline.stringValue = inserted ? "Inserted" : (message == "Listening…" ? "Listening" : message)
            let left: CGFloat = inserted ? 58 : (showsMeter ? meterFrame.maxX + 12 : 37)
            let right: CGFloat = copyResult == nil ? 17 : 42
            let width = ceil(headline.intrinsicContentSize.width) + left + right
            let height: CGFloat = showsMeter ? 42 : 38
            preferredSize = NSSize(width: width, height: height)
            headline.frame = NSRect(x: left, y: floor((height - 18) / 2), width: width - left - right, height: 18)
            closeButton.frame = NSRect(x: 5, y: (height - 26) / 2, width: 26, height: 26)
            check.frame = NSRect(x: 35, y: (height - 16) / 2, width: 16, height: 16)
            copyButton.frame = NSRect(x: width - 35, y: (height - 28) / 2, width: 28, height: 28)
        }
        needsDisplay = true
    }

    var amplitude: Double = 0
    var phase: CapturePhase = .idle
    var time: Double = 0
    var reduceMotion = false
    var dragOffset = NSPoint.zero
    var didDock: ((NSRect, NSRect) -> Void)?
    var didDraw: (() -> Void)?
    private var bars = [Double](repeating: 0, count: 15)
    func step(level: Double, delta: Double) {
        guard showsMeter else { return }
        amplitude = level; time += delta
        for i in bars.indices {
            let shape = 0.30 + 0.70 * pow(abs(sin(Double(i) * 0.72 + (reduceMotion ? 0 : time * 2.2))), 1.2)
            let target = phase == .listening ? level * shape : 0.06 + (reduceMotion ? 0 : 0.10 * (1 + sin(time * 3.4 - Double(i) * 0.26)))
            bars[i] += (target - bars[i]) * (1 - exp(-delta / 0.065))
        }
        setNeedsDisplay(meterFrame)
    }
    override func draw(_ dirtyRect: NSRect) {
        didDraw?()
        let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = detail.isHidden ? frame.height / 2 : 15
        let outline = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        Palette.surface.setFill()
        outline.fill()
        Palette.line.setStroke()
        outline.stroke()
        guard showsMeter else { return }
        let waveform = NSBezierPath()
        for i in bars.indices {
            let height = 3 + CGFloat(bars[i]) * 25
            let rect = NSRect(x: meterFrame.minX + CGFloat(i) * 3.8, y: bounds.midY - height / 2, width: 2.5, height: height)
            waveform.appendRoundedRect(rect, xRadius: 1.25, yRadius: 1.25)
        }
        (phase == .listening ? Palette.mint : Palette.violet).setFill()
        waveform.fill()
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
        panel.setFrame(IndicatorLayout.frame(in: screen.visibleFrame, size: content.preferredSize, anchor: anchor), display: true)
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
    func show(_ message: String, phase: CapturePhase, notice: IndicatorNotice? = nil, copyResult: (() -> Void)? = nil, duration: Double = 2) {
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
        dismissal?.cancel(); content.phase = phase
        content.dismissNotice = [.idle, .cancelled, .failed].contains(phase) ? { [weak self] in self?.hide() } : nil
        content.copyResult = copyResult
        let defaultNotice: IndicatorNotice = copyResult != nil || phase == .failed ? .attention : .status
        content.configure(message: message, notice: notice ?? defaultNotice)
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
