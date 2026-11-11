import AppKit
import AVFoundation
import ApplicationServices
import MurmurCore

@MainActor enum LiveDiagnostics {
    static let request = Notification.Name("local.murmur.live-status-request")
    static var file: URL { Preferences.directory.appendingPathComponent("live-status.json") }
    static func snapshot(controller: DictationController? = nil) -> [String: Any] {
        let resources = Bundle.main.resourceURL!
        var result: [String: Any] = ["pid":ProcessInfo.processInfo.processIdentifier, "timestamp":Date().timeIntervalSince1970, "bundle_path":Bundle.main.bundlePath, "microphone_authorized":AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "accessibility_authorized":AXIsProcessTrusted(), "monitoring_authorized":CGPreflightListenEventAccess(), "speech_model_bundled":FileManager.default.fileExists(atPath: resources.appendingPathComponent("speech-model.bin").path), "editing_model_bundled":FileManager.default.fileExists(atPath: resources.appendingPathComponent("editing-model.gguf").path), "automatic_model_cleanup":Preferences.load().useModel && CleanupQualification.load()?.eligible == true, "local_cleanup_qualified":CleanupQualification.load()?.eligible == true, "delivery_reason":controller?.inserter.lastReason.rawValue ?? "unknown", "delivery":controller?.inserter.lastAttempt ?? [:], "source":"running_app"]
        result["build"] = BuildInfo.details
        if let controller {
            result["indicator"] = controller.indicator.diagnostic
            result["media_pause"] = controller.mediaPauseStatus
            result["speech_evidence"] = controller.speechDiagnostic
            if let data = try? JSONEncoder().encode(controller.trace.entries), let events = try? JSONSerialization.jsonObject(with: data) { result["events"] = events }
            result["background"] = [
                "suspended": controller.isSuspended,
                "phase": controller.sessions.phase.rawValue,
                "microphone_running": controller.microphone.isCapturing,
                "dictation_activity_active": controller.hasDictationActivity,
                "shortcut_warning": controller.hotkeys.availabilityMessage ?? "",
            ] as [String: Any]
        }
        return result
    }
    static func publish(controller: DictationController, focus: [String:Any]? = nil) {
        guard (try? PrivateStorage.directory(Preferences.directory)) != nil else { return }
        var value = snapshot(controller: controller); if let focus { value["focus_check"] = focus }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { try? PrivateStorage.write(data, to: file) }
    }
    static func inspectAndPublish(controller: DictationController) async {
        guard !controller.isSuspended else { publish(controller: controller, focus: ["skipped":"The session is inactive"]); return }
        guard ![CapturePhase.starting, .listening, .processing, .inserting].contains(controller.sessions.phase) else { publish(controller: controller, focus: ["skipped":"Dictation is active"]); return }
        let prefs = controller.preferences
        let continuity = FocusContinuity(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, toggleKey: UInt16(clamping: prefs.toggleKey), holdKey: prefs.holdEnabled ? UInt16(prefs.holdKey.code) : nil)
        defer { continuity.stop() }
        let original = Destination.capture()
        let before = Destination.focusDiagnostics()
        let resolved = await original.resolveEditor(continuity: continuity)
        let current = Destination.capture()
        let reason = resolved.reason(comparedTo: current, focusChanged: continuity.pid != original.pid || continuity.invalidated)
        publish(controller: controller, focus: ["original":original.diagnostic, "resolved":resolved.diagnostic, "current":current.diagnostic, "before":before, "after":Destination.focusDiagnostics(), "reason":reason.rawValue, "focus_tracking_available":continuity.available, "focus_unchanged":!continuity.invalidated, "posted_input":false])
    }
    static func read(inspectFocus: Bool = false) -> [String: Any] {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: "local.murmur.dictation").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        let began = Date().timeIntervalSince1970
        if !peers.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(request, object: nil, userInfo: inspectFocus ? ["inspect_focus":true] : nil, deliverImmediately: true)
            let until = Date().addingTimeInterval(inspectFocus ? 3 : 1)
            while Date() < until {
                if let data = try? Data(contentsOf: file), let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let timestamp = value["timestamp"] as? Double, timestamp >= began, let pid = (value["pid"] as? NSNumber)?.int32Value, peers.contains(where: { $0.processIdentifier == pid }), !inspectFocus || value["focus_check"] != nil { return value }
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
        }
        var result = snapshot(); result["source"] = "command_line"; result["note"] = "Permission context can differ from the launched GUI app."; return result
    }
}
