// meta: created=2026-02-22 updated=2026-02-23 checked=never
import Foundation
import SQLite3
import WeatherCCShared

final class TokenStore {

    let dbPath: String
    private let dirURL: URL

    init(dbPath: String) {
        self.dbPath = dbPath
        self.dirURL = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
    }

    static let shared: TokenStore = {
        guard let container = AppGroupConfig.containerURL else {
            fatalError("[TokenStore] App Group container not available")
        }
        let dir = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
        return TokenStore(dbPath: dir.appendingPathComponent("tokens.db").path)
    }()

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Static convenience (delegates to shared)

    static func sync(directories: [URL]) { shared.sync(directories: directories) }
    static func loadAll() -> [TokenRecord] { shared.loadAll() }
    static func loadRecords(since cutoff: Date) -> [TokenRecord] { shared.loadRecords(since: cutoff) }

    // MARK: - Sync

    /// Incrementally sync JSONL files into SQLite.
    /// Only new or modified files are parsed.
    func sync(directories: [URL]) {
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            NSLog("[TokenStore] Failed to create directory: %@", error.localizedDescription)
            return
        }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            NSLog("[TokenStore] Failed to open DB")
            return
        }
        defer { sqlite3_close(db) }

        createTables(db)

        // 1. Load known files from DB
        let known = loadKnownFiles(db)

        // 2. Scan directories for JSONL files
        var filesToProcess: [(url: URL, modDate: Double)] = []
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = values.contentModificationDate else { continue }

                let modTime = modDate.timeIntervalSince1970
                let path = fileURL.path

                // Skip if already processed with same mod date
                if let knownMod = known[path], abs(knownMod - modTime) < 1.0 {
                    continue
                }

                filesToProcess.append((url: fileURL, modDate: modTime))
            }
        }

        guard !filesToProcess.isEmpty else { return }

        NSLog("[TokenStore] Syncing %d files", filesToProcess.count)

        // 3. Process in a transaction for performance
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        for file in filesToProcess {
            let records = JSONLParser.parseFile(file.url)
            for record in records {
                upsertRecord(db, record)
            }
            markFileProcessed(db, path: file.url.path, modDate: file.modDate, recordCount: records.count)
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        NSLog("[TokenStore] Sync complete: %d files processed", filesToProcess.count)
    }

    // MARK: - Query

    /// Load all token records (for Analysis).
    func loadAll() -> [TokenRecord] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT request_id, timestamp, model, input_tokens, output_tokens,
                   cache_read_tokens, cache_creation_tokens
            FROM token_records ORDER BY timestamp ASC;
            """
        return queryRecords(db, sql: sql)
    }

    /// Load token records since a cutoff date (for fetchPredict).
    func loadRecords(since cutoff: Date) -> [TokenRecord] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let cutoffStr = iso.string(from: cutoff)
        let sql = """
            SELECT request_id, timestamp, model, input_tokens, output_tokens,
                   cache_read_tokens, cache_creation_tokens
            FROM token_records WHERE timestamp >= ? ORDER BY timestamp ASC;
            """
        return queryRecords(db, sql: sql, bindTimestamp: cutoffStr)
    }

    // MARK: - Private: Table Creation

    private func createTables(_ db: OpaquePointer?) {
        let sql = """
            CREATE TABLE IF NOT EXISTS jsonl_files (
                path TEXT PRIMARY KEY,
                mod_date REAL NOT NULL,
                record_count INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS token_records (
                request_id TEXT PRIMARY KEY,
                timestamp TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_token_timestamp ON token_records(timestamp);
            """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("[TokenStore] Failed to create tables")
        }
    }

    // MARK: - Private: Known Files

    private func loadKnownFiles(_ db: OpaquePointer?) -> [String: Double] {
        let sql = "SELECT path, mod_date FROM jsonl_files;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var result: [String: Double] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let pathRaw = sqlite3_column_text(stmt, 0) else { continue }
            let path = String(cString: pathRaw)
            let modDate = sqlite3_column_double(stmt, 1)
            result[path] = modDate
        }
        return result
    }

    // MARK: - Private: Upsert Record

    private func upsertRecord(_ db: OpaquePointer?, _ record: TokenRecord) {
        let sql = """
            INSERT INTO token_records (
                request_id, timestamp, model,
                input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(request_id) DO UPDATE SET
                timestamp = CASE
                    WHEN excluded.output_tokens >= token_records.output_tokens
                    THEN excluded.timestamp ELSE token_records.timestamp END,
                model = CASE
                    WHEN excluded.output_tokens >= token_records.output_tokens
                    THEN excluded.model ELSE token_records.model END,
                input_tokens = CASE
                    WHEN excluded.output_tokens >= token_records.output_tokens
                    THEN excluded.input_tokens ELSE token_records.input_tokens END,
                output_tokens = MAX(excluded.output_tokens, token_records.output_tokens),
                cache_read_tokens = CASE
                    WHEN excluded.output_tokens >= token_records.output_tokens
                    THEN excluded.cache_read_tokens ELSE token_records.cache_read_tokens END,
                cache_creation_tokens = CASE
                    WHEN excluded.output_tokens >= token_records.output_tokens
                    THEN excluded.cache_creation_tokens ELSE token_records.cache_creation_tokens END;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let ts = iso.string(from: record.timestamp)
        sqlite3_bind_text(stmt, 1, (record.requestId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (ts as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (record.model as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(record.inputTokens))
        sqlite3_bind_int(stmt, 5, Int32(record.outputTokens))
        sqlite3_bind_int(stmt, 6, Int32(record.cacheReadTokens))
        sqlite3_bind_int(stmt, 7, Int32(record.cacheCreationTokens))

        sqlite3_step(stmt)
    }

    // MARK: - Private: Mark File Processed

    private func markFileProcessed(_ db: OpaquePointer?, path: String, modDate: Double, recordCount: Int) {
        let sql = "INSERT OR REPLACE INTO jsonl_files (path, mod_date, record_count) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, modDate)
        sqlite3_bind_int(stmt, 3, Int32(recordCount))

        sqlite3_step(stmt)
    }

    // MARK: - Private: Query Helper

    private func queryRecords(_ db: OpaquePointer?, sql: String, bindTimestamp: String? = nil) -> [TokenRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        if let ts = bindTimestamp {
            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
        }

        var results: [TokenRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let reqId = sqlite3_column_text(stmt, 0),
                  let tsRaw = sqlite3_column_text(stmt, 1),
                  let modelRaw = sqlite3_column_text(stmt, 2) else { continue }

            guard let timestamp = iso.date(from: String(cString: tsRaw)) else { continue }

            results.append(TokenRecord(
                timestamp: timestamp,
                requestId: String(cString: reqId),
                model: String(cString: modelRaw),
                speed: "standard",
                inputTokens: Int(sqlite3_column_int(stmt, 3)),
                outputTokens: Int(sqlite3_column_int(stmt, 4)),
                cacheReadTokens: Int(sqlite3_column_int(stmt, 5)),
                cacheCreationTokens: Int(sqlite3_column_int(stmt, 6)),
                webSearchRequests: 0
            ))
        }
        return results
    }
}
