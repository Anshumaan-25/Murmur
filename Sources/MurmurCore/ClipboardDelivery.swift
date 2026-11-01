import AppKit

@MainActor public final class ClipboardDelivery {
    private var generation: UUID?
    private var restoration: (() -> Void)?
    public init() {}
    public func deliver(_ text: String, board: NSPasteboard = .general, delay: Double, paste: () throws -> Void) async throws {
        finish()
        let identity = UUID(); generation = identity
        let snapshot = try PasteboardSnapshot(board)
        board.clearContents()
        guard board.setString(text, forType: .string) else { snapshot.restore(board); throw MurmurError.unavailable("The clipboard could not accept this text.") }
        let count = board.changeCount
        let restore = { _ = snapshot.restore(board, ifUnchangedSince: count) }
        restoration = restore
        do { try paste() } catch { restore(); if generation == identity { generation = nil; restoration = nil }; throw error }
        try? await Task.sleep(nanoseconds: UInt64(min(2, max(0.01, delay)) * 1e9))
        restore()
        if generation == identity { generation = nil; restoration = nil }
    }
    public func finish() { restoration?(); restoration = nil; generation = nil }
}
