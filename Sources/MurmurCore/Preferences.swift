import Foundation

public struct Preferences: Codable {
    public var language = "en-US"
    public var microphone: UInt32 = 0
    public var holdEnabled = true
    public var holdKey = HoldKey.globe
    public var speechEngine = SpeechEngine.automatic
    public var preserveCode = true
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
    enum CodingKeys: String, CodingKey { case language, microphone, holdEnabled, holdKey, speechEngine, preserveCode, handsFree, silenceSeconds, maximumSeconds, clipboardDelay, retention, keepAudio, contextEnabled, spokenReturn, useModel, toggleKey, customSpeechModel, customSpeechExecutable }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? language
        microphone = try values.decodeIfPresent(UInt32.self, forKey: .microphone) ?? microphone
        holdEnabled = try values.decodeIfPresent(Bool.self, forKey: .holdEnabled) ?? holdEnabled
        holdKey = (try? values.decodeIfPresent(HoldKey.self, forKey: .holdKey)) ?? holdKey
        speechEngine = (try? values.decodeIfPresent(SpeechEngine.self, forKey: .speechEngine)) ?? speechEngine
        preserveCode = try values.decodeIfPresent(Bool.self, forKey: .preserveCode) ?? preserveCode
        handsFree = try values.decodeIfPresent(Bool.self, forKey: .handsFree) ?? handsFree
        silenceSeconds = try values.decodeIfPresent(Double.self, forKey: .silenceSeconds) ?? silenceSeconds
        maximumSeconds = try values.decodeIfPresent(Double.self, forKey: .maximumSeconds) ?? maximumSeconds
        clipboardDelay = try values.decodeIfPresent(Double.self, forKey: .clipboardDelay) ?? clipboardDelay
        retention = (try? values.decodeIfPresent(Retention.self, forKey: .retention)) ?? retention
        keepAudio = try values.decodeIfPresent(Bool.self, forKey: .keepAudio) ?? keepAudio
        contextEnabled = try values.decodeIfPresent(Bool.self, forKey: .contextEnabled) ?? contextEnabled
        spokenReturn = try values.decodeIfPresent(Bool.self, forKey: .spokenReturn) ?? spokenReturn
        useModel = try values.decodeIfPresent(Bool.self, forKey: .useModel) ?? useModel
        toggleKey = try values.decodeIfPresent(UInt32.self, forKey: .toggleKey) ?? toggleKey
        customSpeechModel = try values.decodeIfPresent(String.self, forKey: .customSpeechModel) ?? customSpeechModel
        customSpeechExecutable = try values.decodeIfPresent(String.self, forKey: .customSpeechExecutable) ?? customSpeechExecutable
        silenceSeconds = min(10, max(0.5, silenceSeconds.isFinite ? silenceSeconds : 1.5))
        maximumSeconds = min(600, max(5, maximumSeconds.isFinite ? maximumSeconds : 120))
        clipboardDelay = min(2, max(0.1, clipboardDelay.isFinite ? clipboardDelay : 0.35))
    }

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
