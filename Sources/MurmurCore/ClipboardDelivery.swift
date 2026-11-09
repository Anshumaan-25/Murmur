import AppKit

@MainActor public final class ClipboardDelivery {
    private var generation: UUID?
    private var restoration: (() -> Void)?
    public struct Changed: Error {}
    public init() {}
    public func deliver(_ text: String, board: NSPasteboard = .general, delay: Double, validate: () throws -> Void = {}, paste: () throws -> Void) async throws {
        finish()
        let before = board.changeCount
        let snapshot = try PasteboardSnapshot(board)
        try validate()
        try Task.checkCancellation()
        guard board.changeCount == before else { throw Changed() }

        let identity = UUID()
        let marker = NSPasteboard.PasteboardType("local.murmur.clipboard.transaction")
        let item = NSPasteboardItem()
        guard item.setString(identity.uuidString, forType: marker), item.setString(text, forType: .string) else { throw MurmurError.unavailable("The clipboard could not accept this text.") }
        let cleared = board.clearContents()
        guard board.changeCount == cleared else { throw Changed() }
        guard board.writeObjects([item]) else {
            _ = snapshot.restore(board, ifUnchangedSince: cleared)
            throw MurmurError.unavailable("The clipboard could not accept this text.")
        }
        let count = board.changeCount
        let stillOffered = {
            board.changeCount == count && board.string(forType: marker) == identity.uuidString && board.changeCount == count
        }
        let restore = { if stillOffered() { _ = snapshot.restore(board, ifUnchangedSince: count) } }
        generation = identity
        restoration = restore
        do {
            try validate()
            try Task.checkCancellation()
            guard stillOffered() else { throw Changed() }
            try paste()
        } catch { restore(); if generation == identity { generation = nil; restoration = nil }; throw error }
        try? await Task.sleep(nanoseconds: UInt64(min(2, max(0.01, delay)) * 1e9))
        restore()
        if generation == identity { generation = nil; restoration = nil }
    }
    public func finish() { restoration?(); restoration = nil; generation = nil }
}
