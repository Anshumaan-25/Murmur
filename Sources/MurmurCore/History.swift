import Foundation
import CSQLite
import Darwin

public struct Utterance: Codable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var application: String
    public var duration: Double
    public var raw: String
    public var cleaned: String
    public var inserted: String
    public var outcome: String
    public var latency: Double
    public init(id: UUID = UUID(), timestamp: Date = Date(), application: String, duration: Double, raw: String, cleaned: String, inserted: String, outcome: String, latency: Double) {
        self.id = id; self.timestamp = timestamp; self.application = application; self.duration = duration; self.raw = raw; self.cleaned = cleaned; self.inserted = inserted; self.outcome = outcome; self.latency = latency
    }
}
public enum Retention: String, CaseIterable, Codable { case forever, day, never }
public final class HistoryStore {
    private let recordings: URL?
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(path: String) throws {
        let openPath: String
        if path == ":memory:" {
            openPath = path
            recordings = nil
        } else {
            let requested = URL(fileURLWithPath: path)
            // Foundation can retain macOS's /var alias even after resolving a URL.
            // SQLite's NOFOLLOW mode needs the actual spelling of the parent path.
            guard let parent = realpath(requested.deletingLastPathComponent().path, nil) else { throw PrivateStorage.error() }
            defer { free(parent) }
            openPath = String(cString: parent) + "/" + requested.lastPathComponent
            let file = URL(fileURLWithPath: openPath)
            let journal = URL(fileURLWithPath: openPath + "-journal")
            recordings = file.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
            try PrivateStorage.file(file, create: true)
            do { try PrivateStorage.file(journal) }
            catch let error as POSIXError where error.code == .ENOENT {}
        }
        guard sqlite3_open_v2(openPath, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            throw MurmurError.unavailable("Cannot open local history.")
        }
        sqlite3_busy_timeout(connection, 2000)
        try execute("PRAGMA journal_mode=DELETE")
        try execute("PRAGMA secure_delete=ON")
        try execute("CREATE TABLE IF NOT EXISTS utterances (identity TEXT PRIMARY KEY, moment REAL NOT NULL, app TEXT NOT NULL, seconds REAL NOT NULL, recognition TEXT NOT NULL, edited TEXT NOT NULL, delivered TEXT NOT NULL, outcome TEXT NOT NULL, latency REAL NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS lexicon (term TEXT PRIMARY KEY)")
        try execute("CREATE TABLE IF NOT EXISTS expansions (trigger TEXT PRIMARY KEY, replacement TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS app_styles (bundle TEXT PRIMARY KEY, style TEXT NOT NULL)")
    }
    deinit { sqlite3_close(connection) }
    private func execute(_ sql: String) throws { guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw MurmurError.unavailable("Local storage operation failed.") } }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var value: OpaquePointer?; guard sqlite3_prepare_v2(connection, sql, -1, &value, nil) == SQLITE_OK, let value else { throw MurmurError.unavailable("Cannot prepare a storage request.") }; return value
    }
    private func bind(_ strings: [String], to stmt: OpaquePointer, from: Int32 = 1) { for (index, value) in strings.enumerated() { sqlite3_bind_text(stmt, from + Int32(index), value, -1, transient) } }
    private func complete(_ stmt: OpaquePointer) throws { guard sqlite3_step(stmt) == SQLITE_DONE else { throw MurmurError.unavailable("Cannot save local data.") } }
    public func save(_ record: Utterance, retention: Retention = .forever) throws {
        guard retention != .never else { return }
        let stmt = try statement("INSERT OR REPLACE INTO utterances VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"); defer { sqlite3_finalize(stmt) }
        bind([record.id.uuidString], to: stmt); sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970); bind([record.application], to: stmt, from: 3); sqlite3_bind_double(stmt, 4, record.duration); bind([record.raw, record.cleaned, record.inserted, record.outcome], to: stmt, from: 5); sqlite3_bind_double(stmt, 9, record.latency); try complete(stmt)
    }
    public func records(search: String = "") throws -> [Utterance] {
        let stmt = try statement("SELECT * FROM utterances WHERE recognition LIKE ? OR edited LIKE ? ORDER BY moment DESC"); defer { sqlite3_finalize(stmt) }
        bind(["%" + search + "%", "%" + search + "%"], to: stmt)
        func text(_ index: Int32) -> String { sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? "" }
        var result: [Utterance] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let id = UUID(uuidString: text(0)) { result.append(Utterance(id: id, timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)), application: text(2), duration: sqlite3_column_double(stmt, 3), raw: text(4), cleaned: text(5), inserted: text(6), outcome: text(7), latency: sqlite3_column_double(stmt, 8))) } }
        return result
    }
    public func contains(_ id: UUID) throws -> Bool {
        let stmt = try statement("SELECT 1 FROM utterances WHERE identity = ?")
        defer { sqlite3_finalize(stmt) }
        bind([id.uuidString], to: stmt)
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw MurmurError.unavailable("Cannot read local history.")
        }
    }
    public func saveRecording(_ wav: Data, for id: UUID) throws {
        guard let recordings, try contains(id) else { throw MurmurError.unavailable("Recording has no history entry.") }
        try PrivateStorage.directory(recordings)
        try PrivateStorage.write(wav, to: recordings.appendingPathComponent(id.uuidString + ".wav"))
    }
    public func delete(_ id: UUID) throws {
        if let recordings {
            do {
                try PrivateStorage.existingDirectory(recordings)
                try removeRecording(recordings.appendingPathComponent(id.uuidString + ".wav"))
            } catch let error as POSIXError where error.code == .ENOENT {}
        }
        let stmt = try statement("DELETE FROM utterances WHERE identity = ?")
        defer { sqlite3_finalize(stmt) }
        bind([id.uuidString], to: stmt)
        try complete(stmt)
    }
    public func prune(_ retention: Retention, now: Date = Date()) throws {
        if retention == .never { try execute("DELETE FROM utterances"); try execute("VACUUM") }
        if retention == .day { let stmt = try statement("DELETE FROM utterances WHERE moment < ?"); defer { sqlite3_finalize(stmt) }; sqlite3_bind_double(stmt, 1, now.addingTimeInterval(-86400).timeIntervalSince1970); try complete(stmt) }
        try reconcileRecordings()
    }
    private func reconcileRecordings() throws {
        guard let recordings else { return }
        do { try PrivateStorage.existingDirectory(recordings) }
        catch let error as POSIXError where error.code == .ENOENT { return }
        let entries = try FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)
        var failure: Error?
        for file in entries {
            do {
                if file.lastPathComponent.hasPrefix(".keydown-write-"),
                   UUID(uuidString: String(file.lastPathComponent.dropFirst(".keydown-write-".count))) != nil {
                    try removeRecording(file)
                } else if file.pathExtension == "wav", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) {
                    if try contains(id) { try PrivateStorage.file(file) }
                    else { try removeRecording(file) }
                }
            } catch { failure = error }
        }
        if let failure { throw failure }
    }
    private func removeRecording(_ file: URL) throws {
        if unlink(file.path) != 0, errno != ENOENT { throw PrivateStorage.error() }
    }
    public func dictionary() throws -> [String] {
        let stmt = try statement("SELECT term FROM lexicon ORDER BY term"); defer { sqlite3_finalize(stmt) }; var output: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { output.append(String(cString: sqlite3_column_text(stmt, 0))) }; return output
    }
    public func setDictionary(_ terms: [String]) throws {
        try execute("BEGIN IMMEDIATE"); do {
            try execute("DELETE FROM lexicon")
            for term in Set(terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) { let stmt = try statement("INSERT INTO lexicon VALUES (?)"); bind([term], to: stmt); defer { sqlite3_finalize(stmt) }; try complete(stmt) }; try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func values(table: String) throws -> [String: String] {
        guard table == "expansions" || table == "app_styles" else { throw MurmurError.unavailable("Unknown local collection.") }
        let stmt = try statement("SELECT * FROM " + table); defer { sqlite3_finalize(stmt) }; var output: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW { output[String(cString: sqlite3_column_text(stmt, 0))] = String(cString: sqlite3_column_text(stmt, 1)) }; return output
    }
    public func setValues(_ values: [String: String], table: String) throws {
        guard table == "expansions" || table == "app_styles" else { throw MurmurError.unavailable("Unknown local collection.") }
        try execute("BEGIN IMMEDIATE"); do {
            try execute("DELETE FROM " + table)
            for (key, value) in values where !key.isEmpty { let stmt = try statement("INSERT INTO " + table + " VALUES (?, ?)"); defer { sqlite3_finalize(stmt) }; bind([key, value], to: stmt); try complete(stmt) }; try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
