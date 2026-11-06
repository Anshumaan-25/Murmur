import AppKit

@MainActor final class BackgroundLifecycle {
    private enum Interruption: Hashable { case systemSleep, displaySleep, inactiveSession, shutdown }
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var interruptions: Set<Interruption> = []
    private let onSuspensionChanged: (Bool) -> Void

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter, onSuspensionChanged: @escaping (Bool) -> Void) {
        self.center = center
        self.onSuspensionChanged = onSuspensionChanged
        let events: [(Notification.Name, Interruption, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
            (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false),
            (NSWorkspace.willPowerOffNotification, .shutdown, true),
        ]
        for (name, interruption, active) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(interruption, active: active) }
            }
            observers.append(observer)
        }
    }

    private func set(_ interruption: Interruption, active: Bool) {
        let wasSuspended = !interruptions.isEmpty
        if active { interruptions.insert(interruption) }
        else { interruptions.remove(interruption) }
        let isSuspended = !interruptions.isEmpty
        if wasSuspended != isSuspended { onSuspensionChanged(isSuspended) }
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }
}
