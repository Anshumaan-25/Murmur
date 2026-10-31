import AppKit

public struct PasteboardSnapshot {
    public let items: [[NSPasteboard.PasteboardType: Data]]
    public init(_ board: NSPasteboard) throws {
        items = try (board.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw MurmurError.unavailable("The clipboard contains data that cannot be saved safely.") }; copy[type] = data
            }
            return copy
        }
    }
    public func restore(_ board: NSPasteboard) {
        board.clearContents()
        let restored = items.map { types -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, bytes) in types { item.setData(bytes, forType: type) }; return item }
        if !restored.isEmpty { board.writeObjects(restored) }
    }
}
