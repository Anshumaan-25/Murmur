import Foundation

public struct Preferences: Codable {
    public var language = "en-US"
    public var microphone: UInt32 = 0
    public var holdEnabled = true
    public var handsFree = false
    public var silenceSeconds = 1.5
    public var maximumSeconds = 120.0
    public var clipboardDelay = 0.35
    public var retention = Retention.forever
    public var keepAudio = false
    public var contextEnabled = false
    public var spokenReturn = false
    public var useModel = false
    public var toggleKey: UInt32 = 49
    public var customSpeechModel = ""
    public var customSpeechExecutable = ""
    public init() {}
    public static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Murmur", isDirectory: true) }
    public static func load() -> Preferences { guard let data = try? Data(contentsOf: directory.appendingPathComponent("preferences.json")), let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }; return decoded }
    public func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = Self.directory.appendingPathComponent("preferences.json")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public struct UsageStatistics {
    public var words: Int
    public var wordsPerMinute: Double
    public var streak: Int
    public init(_ records: [Utterance], now: Date = Date(), calendar: Calendar = .current) {
        words = records.reduce(0) { $0 + $1.cleaned.split(whereSeparator: \.isWhitespace).count }
        let duration = records.reduce(0) { $0 + $1.duration }
        wordsPerMinute = duration > 0 ? Double(words) * 60 / duration : 0
        let dates = Set(records.map { calendar.startOfDay(for: $0.timestamp) })
        var day = calendar.startOfDay(for: now)
        if !dates.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        streak = 0
        while dates.contains(day) { streak += 1; guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }; day = previous }
    }
}
