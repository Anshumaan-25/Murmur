import AppKit
import AVFoundation
import ApplicationServices
import MurmurCore

@MainActor enum LiveDiagnostics {
    static let request = Notification.Name("local.murmur.live-status-request")
    static var file: URL { Preferences.directory.appendingPathComponent("live-status.json") }
    static func snapshot(controller: DictationController? = nil) -> [String: Any] {
        let resources = Bundle.main.resourceURL!
        return ["pid":ProcessInfo.processInfo.processIdentifier, "timestamp":Date().timeIntervalSince1970, "bundle_path":Bundle.main.bundlePath, "microphone_authorized":AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "accessibility_authorized":AXIsProcessTrusted(), "monitoring_authorized":CGPreflightListenEventAccess(), "speech_model_bundled":FileManager.default.fileExists(atPath: resources.appendingPathComponent("speech-model.bin").path), "editing_model_bundled":FileManager.default.fileExists(atPath: resources.appendingPathComponent("editing-model.gguf").path), "automatic_model_cleanup":Preferences.load().useModel && CleanupQualification.load()?.eligible == true, "local_cleanup_qualified":CleanupQualification.load()?.eligible == true, "delivery_reason":controller?.inserter.lastReason.rawValue ?? "unknown", "source":"running_app"]
    }
    static func publish(controller: DictationController) {
        try? FileManager.default.createDirectory(at: Preferences.directory, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        if let data = try? JSONSerialization.data(withJSONObject: snapshot(controller: controller), options: [.sortedKeys]) { try? data.write(to: file, options: .atomic); try? FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: file.path) }
    }
    static func read() -> [String: Any] {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: "local.murmur.dictation").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        let began = Date().timeIntervalSince1970
        if !peers.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(request, object: nil, userInfo: nil, deliverImmediately: true)
            let until = Date().addingTimeInterval(1)
            while Date() < until {
                if let data = try? Data(contentsOf: file), let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let timestamp = value["timestamp"] as? Double, timestamp >= began, let pid = (value["pid"] as? NSNumber)?.int32Value, peers.contains(where: { $0.processIdentifier == pid }) { return value }
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
        }
        var result = snapshot(); result["source"] = "command_line"; result["note"] = "Permission context can differ from the launched GUI app."; return result
    }
}
