import Foundation

public struct SessionTrace {
    public enum Event: String, Codable { case starting, firstSample, drawDispatched, processing, decoded, cleaned, queued, available, cancelled, suspended, resumed, busy, failed }
    public struct Entry: Codable { public let event: Event; public let uptime: Double; public let session: UUID? }
    public private(set) var entries: [Entry] = []
    public init() {}
    public mutating func record(_ event: Event, session: UUID?) {
        entries.append(Entry(event: event, uptime: ProcessInfo.processInfo.systemUptime, session: session))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
}
