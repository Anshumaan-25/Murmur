import AppKit

/// Stores only normal window frames. The app does not restore window content.
@MainActor final class WindowPlacement {
    private weak var window: NSWindow?
    private let defaults: UserDefaults?
    private let key: String
    private var observers: [NSObjectProtocol] = []
    private var fullscreenTransition = false

    init(window: NSWindow, role: WorkspaceRole, defaults: UserDefaults?) {
        self.window = window
        self.defaults = defaults
        key = "workspaceFrame." + role.rawValue

        window.center()
        if let screen = window.screen ?? NSScreen.main {
            let frames = NSScreen.screens.map(\.visibleFrame)
            let saved = defaults?.string(forKey: key).map(NSRectFromString)
            window.setFrame(Self.reachable(saved ?? window.frame, on: frames,
                                           fallback: screen.visibleFrame, initial: window.frame, minimum: window.minSize), display: false)
        }
        observe(NSWindow.didMoveNotification) { $0.save() }
        observe(NSWindow.didResizeNotification) { $0.save() }
        observe(NSWindow.didDeminiaturizeNotification) { $0.recover() }
        observe(NSWindow.willCloseNotification) { $0.save() }
        observe(NSWindow.willEnterFullScreenNotification) { $0.save(); $0.fullscreenTransition = true }
        observe(NSWindow.didEnterFullScreenNotification) { $0.fullscreenTransition = false }
        observe(NSWindow.willExitFullScreenNotification) { $0.fullscreenTransition = true }
        observe(NSWindow.didExitFullScreenNotification) { $0.fullscreenTransition = false; $0.recover() }
        let displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recover() }
        }
        observers.append(displayObserver)
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func observe(_ name: Notification.Name, perform: @escaping @MainActor (WindowPlacement) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { perform(self) } }
        }
        observers.append(token)
    }

    private func save() {
        guard let window, !fullscreenTransition, !window.styleMask.contains(.fullScreen),
              !window.isMiniaturized else { return }
        defaults?.set(NSStringFromRect(window.frame), forKey: key)
    }

    func fullscreenTransitionFailed() {
        fullscreenTransition = false
        recover()
    }

    func recover() {
        guard let window, !fullscreenTransition, !window.styleMask.contains(.fullScreen),
              !window.isMiniaturized, let fallback = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = Self.reachable(window.frame, on: NSScreen.screens.map(\.visibleFrame),
                                   fallback: fallback, initial: window.frame, minimum: window.minSize)
        if frame != window.frame { window.setFrame(frame, display: window.isVisible) }
    }

    static func reachable(_ proposed: NSRect, on screens: [NSRect], fallback: NSRect,
                          initial: NSRect, minimum: NSSize = .zero) -> NSRect {
        func valid(_ rect: NSRect) -> Bool {
            [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy { $0.isFinite && abs($0) < 1_000_000 }
                && rect.width > 0 && rect.height > 0
        }
        var frame = valid(proposed) ? proposed : initial
        frame.size.width = max(frame.width, minimum.width)
        frame.size.height = max(frame.height, minimum.height)
        if screens.contains(where: { $0.contains(frame) }) { return frame }
        let overlapping = screens.filter { $0.intersects(frame) }.max {
            let left = $0.intersection(frame)
            let right = $1.intersection(frame)
            return left.width * left.height < right.width * right.height
        }
        let screen = overlapping ?? fallback
        let width = min(frame.width, screen.width)
        let height = min(frame.height, screen.height)
        let x = overlapping == nil ? screen.midX - width / 2 : min(max(frame.minX, screen.minX), screen.maxX - width)
        let y = overlapping == nil ? screen.midY - height / 2 : min(max(frame.minY, screen.minY), screen.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
