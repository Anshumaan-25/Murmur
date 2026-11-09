import Foundation

public struct Preferences: Codable {
    public var language = "en-US"
    public var microphone: UInt32 = 0
    public var holdEnabled = true
    public var holdKey = HoldKey.globe
    public var speechEngine = SpeechEngine.automatic
    public var preserveCode = true
    public var dictationMode = DictationMode.automatic
    public var handsFree = false
    public var silenceSeconds = 1.5
    public var maximumSeconds = 120.0
    public var clipboardDelay = 0.35
    public var retention = Retention.forever
    public var keepAudio = false
    public var contextEnabled = false
    public var useModel = false
    public var toggleKey: UInt32 = 49
    public var customSpeechModel = ""
    public var customSpeechExecutable = ""
    public var decoderApproval: DecoderApproval?
    public init() {}
    enum CodingKeys: String, CodingKey { case language, microphone, holdEnabled, holdKey, speechEngine, preserveCode, dictationMode, handsFree, silenceSeconds, maximumSeconds, clipboardDelay, retention, keepAudio, contextEnabled, useModel, toggleKey, customSpeechModel, customSpeechExecutable, decoderApproval }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? language
        microphone = try values.decodeIfPresent(UInt32.self, forKey: .microphone) ?? microphone
        holdEnabled = try values.decodeIfPresent(Bool.self, forKey: .holdEnabled) ?? holdEnabled
        holdKey = (try? values.decodeIfPresent(HoldKey.self, forKey: .holdKey)) ?? holdKey
        speechEngine = (try? values.decodeIfPresent(SpeechEngine.self, forKey: .speechEngine)) ?? speechEngine
        preserveCode = try values.decodeIfPresent(Bool.self, forKey: .preserveCode) ?? preserveCode
        dictationMode = (try? values.decodeIfPresent(DictationMode.self, forKey: .dictationMode)) ?? dictationMode
        handsFree = try values.decodeIfPresent(Bool.self, forKey: .handsFree) ?? handsFree
        silenceSeconds = try values.decodeIfPresent(Double.self, forKey: .silenceSeconds) ?? silenceSeconds
        maximumSeconds = try values.decodeIfPresent(Double.self, forKey: .maximumSeconds) ?? maximumSeconds
        clipboardDelay = try values.decodeIfPresent(Double.self, forKey: .clipboardDelay) ?? clipboardDelay
        retention = (try? values.decodeIfPresent(Retention.self, forKey: .retention)) ?? retention
        keepAudio = try values.decodeIfPresent(Bool.self, forKey: .keepAudio) ?? keepAudio
        contextEnabled = try values.decodeIfPresent(Bool.self, forKey: .contextEnabled) ?? contextEnabled
        useModel = try values.decodeIfPresent(Bool.self, forKey: .useModel) ?? useModel
        toggleKey = try values.decodeIfPresent(UInt32.self, forKey: .toggleKey) ?? toggleKey
        customSpeechModel = try values.decodeIfPresent(String.self, forKey: .customSpeechModel) ?? customSpeechModel
        customSpeechExecutable = try values.decodeIfPresent(String.self, forKey: .customSpeechExecutable) ?? customSpeechExecutable
        decoderApproval = try? values.decodeIfPresent(DecoderApproval.self, forKey: .decoderApproval)
        silenceSeconds = min(10, max(0.5, silenceSeconds.isFinite ? silenceSeconds : 1.5))
        maximumSeconds = min(600, max(5, maximumSeconds.isFinite ? maximumSeconds : 120))
        clipboardDelay = min(2, max(0.1, clipboardDelay.isFinite ? clipboardDelay : 0.35))
    }

    public static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Murmur", isDirectory: true) }
    public static func load() -> Preferences { guard let data = try? Data(contentsOf: directory.appendingPathComponent("preferences.json")), let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }; return decoded }
    public func save() throws {
        try PrivateStorage.directory(Self.directory)
        let url = Self.directory.appendingPathComponent("preferences.json")
        try PrivateStorage.write(JSONEncoder().encode(self), to: url)
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
