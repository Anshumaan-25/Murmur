import Foundation

private final class DeadlineState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []
    func install(_ value: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(with: result) }
        else { continuation = value; lock.unlock() }
    }
    func register(_ workers: [Task<Void, Never>]) {
        lock.lock(); let finished = result != nil; if !finished { tasks = workers }; lock.unlock()
        if finished { workers.forEach { $0.cancel() } }
    }
    func resolve(_ value: Result<Value, Error>) {
        lock.lock(); guard result == nil else { lock.unlock(); return }
        result = value; let waiting = continuation; continuation = nil; let workers = tasks; tasks = []; lock.unlock()
        workers.forEach { $0.cancel() }; waiting?.resume(with: value)
    }
}
public enum Deadline {
    public static func run<Value: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let state = DeadlineState<Value>()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let worker = Task { do { state.resolve(.success(try await operation())) } catch { state.resolve(.failure(error)) } }
                let timer = Task {
                    do { try await Task.sleep(nanoseconds: UInt64(max(0.001, seconds) * 1e9)); state.resolve(.failure(MurmurError.deadline)) } catch {}
                }
                state.register([worker, timer])
            }
        }, onCancel: { state.resolve(.failure(CancellationError())) })
    }
}
