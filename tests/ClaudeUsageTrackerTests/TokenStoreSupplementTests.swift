// Supplement for: tests/ClaudeUsageTrackerTests/TokenStoreTests.swift
// Generated from: _documents/spec/data/token-store.md
// Covers: UT-01, UT-02, UT-14, UT-41, UT-42, UT-52, UT-53

import XCTest
@testable import ClaudeUsageTracker

final class TokenStoreSupplementTests: XCTestCase {

    private var tmpDir: URL!
    private var store: TokenStore!
    private var jsonlDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStoreSupplementTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = TokenStore(dbPath: tmpDir.appendingPathComponent("tokens.db").path)

        jsonlDir = tmpDir.appendingPathComponent("jsonl")
        try! FileManager.default.createDirectory(at: jsonlDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func writeJSONLFile(name: String, lines: [String]) -> URL {
        TokenStoreTestHelpers.writeJSONLFile(name: name, lines: lines, in: jsonlDir)
    }

    private func makeAssistantLine(
        requestId: String,
        timestamp: String = "2026-02-22T10:00:00.000Z",
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 200
    ) -> String {
        TokenStoreTestHelpers.makeAssistantLine(
            requestId: requestId,
            timestamp: timestamp,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    // MARK: - UT-01: shared singleton — XCTest environment uses tmp directory

    // Spec 3.1 UT-01: DEBUG + XCTest 環境では tmpDir/ClaudeUsageTracker-test-shared/tokens.db を使用する。
    // ProcessInfo XCTestConfigurationFilePath != nil のとき App Group にフォールバックしない。
    func testShared_inXCTestEnvironment_usesTmpDirectory() {
        // XCTest 実行中は ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // → shared の dbPath は tmpDir 配下になるはずで、App Group コンテナを指してはならない。
        let sharedPath = TokenStore.shared.dbPath
        let appGroupPrefix = "/Library/Group Containers/"
        XCTAssertFalse(
            sharedPath.contains(appGroupPrefix),
            "UT-01: In XCTest environment, shared.dbPath should NOT point to App Group container. Got: \(sharedPath)"
        )
    }

    // MARK: - UT-02: shared singleton — normal execution uses App Group container

    // Spec 3.1 UT-02: 通常実行時は AppGroupConfig.containerURL/Library/Application Support/{appName}/tokens.db を使用する。
    // XCTest 環境では直接検証できないため、dbPath の構造が仕様の命名規則に従うことを確認する。
    func testShared_dbPath_endsWithTokensDb() {
        // shared は常に "tokens.db" というファイル名を使用する（仕様共通部分）。
        let sharedPath = TokenStore.shared.dbPath
        XCTAssertTrue(
            sharedPath.hasSuffix("tokens.db"),
            "UT-02: shared.dbPath should end with 'tokens.db'. Got: \(sharedPath)"
        )
    }

    // MARK: - UT-14: sync() — .jsonl 以外の拡張子はスキップ

    // Spec 3.2 UT-14: .jsonl 以外の拡張子を持つファイルは同期をスキップする (pathExtension != "jsonl")。
    func testSync_nonJsonlExtension_isSkipped() {
        // .txt ファイルを配置
        let txtContent = makeAssistantLine(requestId: "req_txt")
        let txtURL = jsonlDir.appendingPathComponent("data.txt")
        try! txtContent.write(to: txtURL, atomically: true, encoding: .utf8)

        // .json ファイルを配置
        let jsonContent = makeAssistantLine(requestId: "req_json")
        let jsonURL = jsonlDir.appendingPathComponent("data.json")
        try! jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)

        // .log ファイルを配置
        let logContent = makeAssistantLine(requestId: "req_log")
        let logURL = jsonlDir.appendingPathComponent("data.log")
        try! logContent.write(to: logURL, atomically: true, encoding: .utf8)

        store.sync(directories: [jsonlDir])
        let records = store.loadAll()

        // .jsonl 以外は全てスキップされるのでレコードは 0 件
        XCTAssertEqual(
            records.count, 0,
            "UT-14: Files with extensions other than .jsonl should be skipped. Got \(records.count) records."
        )
    }

    // UT-14 補足: .jsonl ファイルは処理され、非 .jsonl ファイルは混在時もスキップされる。
    func testSync_onlyJsonlFilesAreProcessed_whenMixed() {
        // .jsonl ファイル（処理されるべき）
        let _ = writeJSONLFile(name: "valid.jsonl", lines: [
            makeAssistantLine(requestId: "req_valid"),
        ])

        // .txt ファイル（スキップされるべき）
        let txtContent = makeAssistantLine(requestId: "req_should_skip")
        try! txtContent.write(
            to: jsonlDir.appendingPathComponent("skip.txt"),
            atomically: true, encoding: .utf8
        )

        store.sync(directories: [jsonlDir])
        let records = store.loadAll()

        XCTAssertEqual(records.count, 1, "UT-14: Only .jsonl files should be processed in mixed directory.")
        XCTAssertEqual(records[0].requestId, "req_valid")
    }

    // MARK: - UT-41: loadRecords(since:) — cutoff が未来日時のとき空配列を返す

    // Spec 3.5 UT-41: cutoff = 未来日時のとき、全レコードが cutoff 未満となり空配列を返す。
    func testLoadRecords_futureCutoff_returnsEmpty() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001", timestamp: "2026-02-22T10:00:00.000Z"),
            makeAssistantLine(requestId: "req_002", timestamp: "2026-02-22T11:00:00.000Z"),
        ])
        store.sync(directories: [jsonlDir])

        // cutoff を遠い未来に設定
        let futureCutoff = Date.distantFuture

        let records = store.loadRecords(since: futureCutoff)
        XCTAssertEqual(
            records.count, 0,
            "UT-41: loadRecords(since: distantFuture) should return empty array."
        )
    }

    // MARK: - UT-42: loadRecords(since:) — cutoff が過去日時のとき全件返す

    // Spec 3.5 UT-42: cutoff = 過去日時のとき、全レコードが cutoff 以降となり全件返す。
    func testLoadRecords_pastCutoff_returnsAll() {
        let _ = writeJSONLFile(name: "test.jsonl", lines: [
            makeAssistantLine(requestId: "req_001", timestamp: "2026-02-22T10:00:00.000Z"),
            makeAssistantLine(requestId: "req_002", timestamp: "2026-02-22T11:00:00.000Z"),
            makeAssistantLine(requestId: "req_003", timestamp: "2026-02-22T12:00:00.000Z"),
        ])
        store.sync(directories: [jsonlDir])

        // cutoff を遠い過去に設定
        let pastCutoff = Date.distantPast

        let records = store.loadRecords(since: pastCutoff)
        XCTAssertEqual(
            records.count, 3,
            "UT-42: loadRecords(since: distantPast) should return all records."
        )
    }

    // MARK: - UT-52: queryRecords() — NULL カラム値を持つ行はスキップ

    // Spec 3.6 UT-52: reqId / tsRaw / modelRaw が NULL のとき、その行を skip (continue) する。
    // TokenStore は guard let で nil チェックしているため、NULL 行は結果に含まれない。
    // 直接 NULL を INSERT するには SQLite を操作する必要があるが、
    // spec はソース非参照のため「NULL を含む行が結果に含まれない」という
    // 振る舞いを JSONL 経由で観測可能な範囲で検証する。
    //
    // requestId が空文字列のレコードは PRIMARY KEY 制約違反にならないが、
    // 仕様上 guard let reqId = ... のチェックで NULL の場合にスキップされる。
    // ここでは、正常レコードと NULL 相当（フィールド欠損）レコードが混在しても
    // 正常レコードのみが返されることを確認する。
    func testQueryRecords_rowsWithMissingRequiredFields_areSkipped() {
        // requestId フィールドが欠損した不正行（JSON として有効だが requestId なし）
        let malformedLine = #"{"type":"assistant","timestamp":"2026-02-22T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        // 正常行
        let validLine = makeAssistantLine(requestId: "req_valid")

        let _ = writeJSONLFile(name: "mixed.jsonl", lines: [malformedLine, validLine])
        store.sync(directories: [jsonlDir])

        let records = store.loadAll()
        // 不正行は JSONLParser がスキップするか、DB に挿入されない
        // 正常レコードのみが返されること
        let ids = records.map { $0.requestId }
        XCTAssertFalse(
            ids.contains(""),
            "UT-52: Rows with missing/NULL requestId should not appear in results."
        )
        XCTAssertTrue(
            ids.contains("req_valid"),
            "UT-52: Valid rows should still be returned even when mixed with malformed rows."
        )
    }

    // MARK: - UT-53: queryRecords() — ISO8601 パース不可の timestamp 行はスキップ

    // Spec 3.6 UT-53: timestamp が ISO8601 パース不可のとき、その行を skip (continue) する。
    // iso.date(from:) == nil となる行は結果に含まれない。
    func testQueryRecords_invalidTimestamp_rowIsSkipped() {
        // timestamp が ISO8601 として不正な行
        let invalidTsLine = #"{"type":"assistant","requestId":"req_bad_ts","timestamp":"NOT-A-DATE","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        // 正常行
        let validLine = makeAssistantLine(requestId: "req_good_ts")

        let _ = writeJSONLFile(name: "ts_test.jsonl", lines: [invalidTsLine, validLine])
        store.sync(directories: [jsonlDir])

        let records = store.loadAll()
        let ids = records.map { $0.requestId }
        XCTAssertFalse(
            ids.contains("req_bad_ts"),
            "UT-53: Row with unparseable ISO8601 timestamp should be skipped."
        )
        XCTAssertTrue(
            ids.contains("req_good_ts"),
            "UT-53: Valid rows should still be returned even when mixed with invalid-timestamp rows."
        )
    }
}
