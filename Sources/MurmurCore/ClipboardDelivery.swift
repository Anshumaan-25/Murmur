import AppKit

@MainActor public final class ClipboardDelivery {
    private var pending: (id: UUID, restore: () -> Void)?
    public struct Changed: Error {}
    public init() {}
    @discardableResult public func deliver(_ text: String, board: NSPasteboard = .general, delay: Double,
                                          validate: () throws -> Void = {}, verifyPaste: (() -> Bool)? = nil,
                                          keepTextIfUnconfirmed: Bool = false,
                                          paste: () throws -> Void) async throws -> Bool {
        finish()
        let before = board.changeCount
        let snapshot = try PasteboardSnapshot(board)
        try validate()
        try Task.checkCancellation()

        let identity = UUID()
        let marker = NSPasteboard.PasteboardType("local.murmur.clipboard.transaction")
        let item = NSPasteboardItem()
        // Clipboard history tools can skip the temporary paste without hiding explicit copies.
        guard item.setString(identity.uuidString, forType: marker), item.setString(text, forType: .string),
              item.setData(Data(), forType: .transientContent) else {
            throw MurmurError.unavailable("The clipboard could not accept this text.")
        }
        guard board.changeCount == before else { throw Changed() }
        let cleared = board.clearContents()
        guard board.changeCount == cleared else { throw Changed() }
        guard board.writeObjects([item]) else {
            snapshot.restore(board, ifUnchangedSince: cleared)
            throw MurmurError.unavailable("The clipboard could not accept this text.")
        }
        let count = board.changeCount
        let stillOffered = {
            board.changeCount == count && board.string(forType: marker) == identity.uuidString && board.changeCount == count
        }
        var restoreOriginal = true
        pending = (identity, {
            guard stillOffered() else { return }
            if restoreOriginal {
                snapshot.restore(board, ifUnchangedSince: count)
            } else {
                // A queued paste may still read the clipboard. Retain the
                // dictation as plain text so it cannot paste the old contents.
                let generation = board.clearContents()
                if board.changeCount == generation { board.setString(text, forType: .string) }
            }
        })
        defer {
            if pending?.id == identity { finish() }
        }

        try validate()
        try Task.checkCancellation()
        guard stillOffered() else { throw Changed() }
        try paste()
        restoreOriginal = !keepTextIfUnconfirmed
        let clock = ContinuousClock()
        let postedAt = clock.now

        let restoreAt = postedAt + .seconds(min(2, max(0.01, delay)))
        try? await clock.sleep(until: restoreAt)
        guard let verifyPaste else { return false }

        // A readable editor can show the effect of a delayed paste. Keep the text
        // available briefly beyond the normal delay while waiting for that change.
        let deadline = max(restoreAt, postedAt + .seconds(1.2))
        while !Task.isCancelled, pending?.id == identity, stillOffered() {
            if verifyPaste() {
                restoreOriginal = true
                return true
            }
            let now = clock.now
            guard now < deadline else { break }
            try? await clock.sleep(until: min(deadline, now + .milliseconds(75)))
        }
        return false
    }
    public func finish() {
        let restore = pending?.restore
        pending = nil
        restore?()
    }
}
