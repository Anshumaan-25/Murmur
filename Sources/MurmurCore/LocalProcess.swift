import CryptoKit
import Darwin
import Foundation

public struct DecoderApproval: Codable, Sendable {
    public let path: String
    private let sha256: Data

    public init(executable: URL) throws {
        let canonical = executable.resolvingSymlinksInPath()
        path = canonical.path
        sha256 = Data(SHA256.hash(data: try Self.read(canonical)))
    }

    fileprivate func stage(_ executable: URL, in directory: URL) throws -> URL {
        let canonical = executable.resolvingSymlinksInPath()
        guard canonical.path == path else { throw Self.changed }
        let bytes = try Self.read(canonical)
        guard Data(SHA256.hash(data: bytes)) == sha256 else { throw Self.changed }
        let staged = directory.appendingPathComponent("approved-decoder")
        try bytes.write(to: staged, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        return staged
    }

    private static var changed: MurmurError { .unavailable("The custom decoder changed. Select and approve it again.") }

    private static func read(_ executable: URL) throws -> Data {
        let fd = open(executable.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw changed }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        let limit = 128 * 1024 * 1024
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o111 != 0,
              info.st_size > 0, info.st_size <= limit,
              let bytes = try file.read(upToCount: limit + 1), bytes.count == info.st_size else { throw changed }
        return bytes
    }
}

private final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

public enum LocalProcess {
    private static let worker = DispatchQueue(label: "local.murmur.decoder", qos: .userInitiated, attributes: .concurrent)
    private static let decoderSlot = DispatchSemaphore(value: 1)
    private static let outputLimit = 1024 * 1024
    private static let runLock = NSLock()
    private static var running = 0

    public static var hasPendingWork: Bool { runLock.withLock { running > 0 } }

    public static func run(executable: URL, arguments: [String], input: Data, timeout: TimeInterval, approval: DecoderApproval? = nil) async throws -> String {
        guard timeout.isFinite, timeout > 0, input.count <= 32 * 1024 * 1024,
              !([executable.path] + arguments).contains(where: { $0.utf8.contains(0) }) else {
            throw MurmurError.unavailable("Invalid local decoder input or deadline.")
        }
        try Task.checkCancellation()
        runLock.withLock { running += 1 }
        defer { runLock.withLock { running -= 1 } }
        let cancellation = ProcessCancellation()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let result: String = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                worker.async {
                    continuation.resume(with: Result {
                        try execute(executable, arguments: arguments, input: input, deadline: deadline, cancellation: cancellation, approval: approval)
                    })
                }
            }
        }, onCancel: { cancellation.cancel() })
        try Task.checkCancellation()
        return result
    }

    private static func execute(_ executable: URL, arguments: [String], input: Data, deadline: Double, cancellation: ProcessCancellation, approval: DecoderApproval?) throws -> String {
        func checkDeadline() throws {
            try cancellation.check()
            if ProcessInfo.processInfo.systemUptime >= deadline {
                throw MurmurError.unavailable("The local decoder timed out.")
            }
        }
        while decoderSlot.wait(timeout: .now() + .milliseconds(20)) != .success { try checkDeadline() }
        defer { decoderSlot.signal() }
        try checkDeadline()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let program = try approval?.stage(executable, in: directory) ?? executable

        var source = try makePipe()
        defer { source.forEach { if $0 >= 0 { close($0) } } }
        var destination = try makePipe()
        defer { destination.forEach { if $0 >= 0 { close($0) } } }
        try check(fcntl(source[1], F_SETNOSIGPIPE, 1) == -1 ? errno : 0)
        for fd in [source[1], destination[0]] {
            try check(fcntl(fd, F_SETFL, O_NONBLOCK) == -1 ? errno : 0)
        }

        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_adddup2(&actions, source[0], STDIN_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, destination[1], STDOUT_FILENO))
        try check(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0))
        try check(posix_spawn_file_actions_addchdir(&actions, directory.path))

        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))

        let environment = ["PATH=/usr/bin:/bin", "HOME=\(directory.path)", "TMPDIR=\(directory.path)",
                           "XDG_CONFIG_HOME=\(directory.path)", "XDG_CACHE_HOME=\(directory.path)", "LANG=en_US.UTF-8"]
        var argv = ([program.path] + arguments).map { strdup($0) } + [nil]
        var envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        try checkDeadline()
        var pid: pid_t = 0
        try check(posix_spawn(&pid, program.path, &actions, &attributes, &argv, &envp))
        var reaped = false
        defer {
            if !reaped {
                kill(-pid, SIGKILL)
                kill(pid, SIGKILL)
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) == 0 {
                    let child = pid
                    runLock.withLock { running += 1 }
                    DispatchQueue.global(qos: .utility).async {
                        defer { runLock.withLock { running -= 1 } }
                        var status: Int32 = 0
                        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
                    }
                }
            }
        }
        close(source[0]); source[0] = -1
        close(destination[1]); destination[1] = -1

        var offset = 0
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            try checkDeadline()
            if offset == input.count, source[1] >= 0 { close(source[1]); source[1] = -1 }
            if destination[0] < 0 {
                var event = siginfo_t()
                let waited = waitid(P_PID, id_t(pid), &event, WEXITED | WNOHANG | WNOWAIT)
                if waited == 0 && event.si_pid == pid {
                    // Keep the leader's PID reserved while terminating its remaining group.
                    kill(-pid, SIGKILL)
                    var status: Int32 = 0
                    var child: pid_t
                    repeat { child = waitpid(pid, &status, 0) } while child < 0 && errno == EINTR
                    if child != pid { try check(errno) }
                    reaped = true
                    try checkDeadline()
                    guard status == 0, let text = String(data: output, encoding: .utf8) else {
                        throw MurmurError.unavailable("Local decoder stopped before completion.")
                    }
                    return text
                }
                if waited < 0 && errno != EINTR { try check(errno) }
            }
            var events = [pollfd(fd: source[1], events: Int16(POLLOUT), revents: 0),
                          pollfd(fd: destination[0], events: Int16(POLLIN), revents: 0)]
            let ready = poll(&events, 2, 20)
            if ready < 0 && errno != EINTR { try check(errno) }
            if events[0].revents != 0 {
                let count = input.withUnsafeBytes { write(source[1], $0.baseAddress?.advanced(by: offset), min(16 * 1024, input.count - offset)) }
                if count > 0 { offset += count }
                else if count < 0 && errno == EPIPE { close(source[1]); source[1] = -1 }
                else if count < 0 && errno != EAGAIN && errno != EINTR { try check(errno) }
            }
            if events[1].revents != 0 {
                let count = read(destination[0], &buffer, buffer.count)
                if count == 0 { close(destination[0]); destination[0] = -1 }
                else if count > 0 {
                    guard output.count + count <= outputLimit else { throw MurmurError.unavailable("Local decoder output exceeded the limit.") }
                    output.append(contentsOf: buffer.prefix(count))
                } else if errno != EAGAIN && errno != EINTR { try check(errno) }
            }
        }
    }

    private static func makePipe() throws -> [Int32] {
        var pair: [Int32] = [-1, -1]
        try check(pipe(&pair) == -1 ? errno : 0)
        do {
            for index in pair.indices where pair[index] < 3 {
                let duplicate = fcntl(pair[index], F_DUPFD_CLOEXEC, 3)
                try check(duplicate == -1 ? errno : 0)
                close(pair[index])
                pair[index] = duplicate
            }
            return pair
        } catch {
            pair.forEach { close($0) }
            throw error
        }
    }

    private static func check(_ code: Int32) throws {
        if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    }
}
