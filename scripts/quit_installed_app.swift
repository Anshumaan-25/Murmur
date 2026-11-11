import AppKit
import Darwin

// Launch Services owns the identity used for the quit request. The paths
// restrict it to the app copies that this installation can replace.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, let timeout = Double(arguments[1]),
      timeout.isFinite, (0.1...120).contains(timeout) else { exit(64) }
let identifier = arguments[0]
let paths = Set(arguments.dropFirst(2))
let deadline = ProcessInfo.processInfo.systemUptime + timeout

func matches(_ application: NSRunningApplication) -> Bool {
    guard !application.isTerminated, application.bundleIdentifier == identifier,
          let executable = application.executableURL, paths.contains(executable.path) else { return false }
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    guard proc_pidpath(application.processIdentifier, &buffer, UInt32(buffer.count)) > 0 else { return false }
    return String(cString: buffer) == executable.path
}

func candidates() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter {
        guard !$0.isTerminated, let executable = $0.executableURL else { return false }
        return paths.contains(executable.path)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let running = candidates()
guard running.count <= 1 else { fail("Close the extra Keydown instance and retry the installation.") }
if let application = running.first {
    guard matches(application), application.terminate() else {
        fail("Keydown could not be asked to quit. Installation stopped.")
    }
    while !application.isTerminated, ProcessInfo.processInfo.systemUptime < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        Thread.sleep(forTimeInterval: 0.025)
    }
    guard application.isTerminated else {
        fail("Keydown is still running. Resolve any open dialogs or quit it, then retry the installation.")
    }
}
guard candidates().isEmpty else { fail("Keydown reopened during the update. Installation stopped.") }
