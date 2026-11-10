import Foundation
import Darwin

/// A pause-only compatibility adapter for the macOS Now Playing session.
/// MediaRemote is private: symbol availability and dispatch success are not playback confirmation.
/// Never read playback metadata, impersonate Apple, synthesize a toggle, or change output volume.
@MainActor final class SystemMediaPause {
    static let shared = SystemMediaPause()
    private typealias Send = @convention(c) (UInt32, CFDictionary?) -> Bool
    private let handle: UnsafeMutableRawPointer?
    private let send: Send?
    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_LOCAL)
        self.handle = handle
        self.send = handle.flatMap { dlsym($0, "MRMediaRemoteSendCommand") }.map { unsafeBitCast($0, to: Send.self) }
    }
    // Keep the system framework loaded for the process lifetime; callbacks may outlive dispatch.
    func pause() -> Bool { send?(1, nil) ?? false } // kMRPause, never kMRTogglePlayPause.
}
