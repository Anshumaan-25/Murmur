import AppKit

enum WorkspaceRole: String { case hub, historyReview, suggestionReview, practice }

@MainActor final class AppPresentation {
    private var windows: [NSWindow] = []
    private let policy: () -> NSApplication.ActivationPolicy
    private let setPolicy: (NSApplication.ActivationPolicy) -> Bool
    private let activate: () -> Void
    private let onFailure: () -> Void
    private var observers: [NSObjectProtocol] = []
    private var pendingDemotion = false
    private let canDemote: @MainActor () -> Bool

    init(policy: @escaping @MainActor () -> NSApplication.ActivationPolicy = { NSApp.activationPolicy() },
         setPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Bool = { NSApp.setActivationPolicy($0) },
         activate: @escaping @MainActor () -> Void = { NSApp.activate() },
         canDemote: @escaping @MainActor () -> Bool = {
             NSApp.modalWindow == nil && !NSApp.windows.contains { $0.attachedSheet != nil }
         },
         onFailure: @escaping @MainActor () -> Void = {}) {
        self.policy = policy
        self.setPolicy = setPolicy
        self.activate = activate
        self.onFailure = onFailure
        self.canDemote = canDemote
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow { self?.didClose(window) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settlePolicy() }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func present(_ window: NSWindow) {
        pendingDemotion = false
        windows.removeAll { $0 === window }
        windows.append(window)
        if policy() != .regular, !setPolicy(.regular) { onFailure() }
        activate()
        window.makeKeyAndOrderFront(nil)
    }

    func reopen(hasVisibleWindows: Bool) -> Bool {
        guard let window = windows.last else { return false }
        if !hasVisibleWindows { present(window) }
        return true
    }

    private func didClose(_ window: NSWindow) {
        if windows.contains(where: { $0 === window }) {
            windows.removeAll { $0 === window }
            pendingDemotion = windows.isEmpty
        }
        settlePolicy()
    }

    private func settlePolicy() {
        guard pendingDemotion else { return }
        // Let AppKit finish its window or sheet transition before demoting.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingDemotion, self.canDemote() else { return }
            self.pendingDemotion = false
            if self.policy() != .accessory, !self.setPolicy(.accessory) { self.onFailure() }
        }
    }
}
