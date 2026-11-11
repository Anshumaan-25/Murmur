import AppKit
import AVFoundation
import Speech

enum PermissionStatus {
    case notDetermined, denied, restricted, authorized, unavailable

    var text: String {
        switch self {
        case .notDetermined: return "Permission needed"
        case .denied: return "Denied. Allow access in System Settings."
        case .restricted: return "Restricted by macOS or device management."
        case .authorized: return "Allowed"
        case .unavailable: return "Permission status unavailable"
        }
    }

    var buttonTitle: String {
        switch self {
        case .denied: return "Open Privacy Settings…"
        case .authorized: return "Access Allowed"
        default: return "Request Access"
        }
    }

    var canAct: Bool { self == .notDetermined || self == .denied }
}

@MainActor final class PermissionAccess {
    enum Kind: String, Hashable {
        case microphone = "Microphone"
        case speech = "SpeechRecognition"
    }

    let status: @MainActor (Kind) -> PermissionStatus
    private let request: @MainActor (Kind) async -> Void
    private let open: @MainActor (Kind) -> Bool
    private(set) var pending: Set<Kind> = []

    init(status: @escaping @MainActor (Kind) -> PermissionStatus = { PermissionAccess.systemStatus($0) },
         request: @escaping @MainActor (Kind) async -> Void = { await PermissionAccess.systemRequest($0) },
         open: @escaping @MainActor (Kind) -> Bool = { PermissionAccess.openSettings($0) }) {
        self.status = status
        self.request = request
        self.open = open
    }

    func perform(_ kind: Kind, refresh: () -> Void) async -> Bool {
        guard !pending.contains(kind) else { return true }
        switch status(kind) {
        case .notDetermined:
            pending.insert(kind)
            refresh()
            await request(kind)
            pending.remove(kind)
            refresh()
            return true
        case .denied: return open(kind)
        case .authorized, .restricted, .unavailable: return true
        }
    }

    private static func systemStatus(_ kind: Kind) -> PermissionStatus {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            case .authorized: return .authorized
            @unknown default: return .unavailable
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            case .authorized: return .authorized
            @unknown default: return .unavailable
            }
        }
    }

    private static func systemRequest(_ kind: Kind) async {
        switch kind {
        case .microphone: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speech:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
    }

    private static func openSettings(_ kind: Kind) -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + kind.rawValue) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
