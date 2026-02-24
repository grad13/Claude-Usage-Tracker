import XCTest
import WeatherCCShared

final class SnapshotStoreTests: XCTestCase {

    private var tempDir: URL!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotStoreTests-\(UUID().uuidString)")
        tempURL = tempDir.appendingPathComponent("snapshot.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Round-Trip

    func testSaveAndLoad_roundTrip_allFields() {
        let now = Date(timeIntervalSince1970: 1740000000)
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 55.5,
            sevenDayPercent: 22.2,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(86400),
            fiveHourHistory: [HistoryPoint(timestamp: now, percent: 55.5)],
            sevenDayHistory: [HistoryPoint(timestamp: now, percent: 22.2)],
            isLoggedIn: true,
            predictFiveHourCost: 3.14,
            predictSevenDayCost: 9.99
        )

        SnapshotStore.save(snapshot, to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHourPercent, 55.5)
        XCTAssertEqual(loaded?.sevenDayPercent, 22.2)
        XCTAssertEqual(loaded?.isLoggedIn, true)
        XCTAssertEqual(loaded?.fiveHourHistory.count, 1)
        XCTAssertEqual(loaded?.sevenDayHistory.count, 1)
        XCTAssertEqual(loaded?.fiveHourHistory.first?.percent, 55.5)
        XCTAssertEqual(loaded?.sevenDayHistory.first?.percent, 22.2)
        XCTAssertEqual(loaded?.predictFiveHourCost, 3.14)
        XCTAssertEqual(loaded?.predictSevenDayCost, 9.99)
        XCTAssertNotNil(loaded?.fiveHourResetsAt)
        XCTAssertEqual(loaded!.fiveHourResetsAt!.timeIntervalSince1970,
                       now.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(loaded?.sevenDayResetsAt)
        XCTAssertEqual(loaded!.sevenDayResetsAt!.timeIntervalSince1970,
                       now.addingTimeInterval(86400).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded!.timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 1)
    }

    func testSaveAndLoad_roundTrip_nilOptionals() {
        let now = Date(timeIntervalSince1970: 1740000000)
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: nil,
            sevenDayPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: false,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        SnapshotStore.save(snapshot, to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.fiveHourPercent)
        XCTAssertNil(loaded?.sevenDayPercent)
        XCTAssertNil(loaded?.fiveHourResetsAt)
        XCTAssertNil(loaded?.sevenDayResetsAt)
        XCTAssertEqual(loaded?.fiveHourHistory.count, 0)
        XCTAssertEqual(loaded?.sevenDayHistory.count, 0)
        XCTAssertEqual(loaded?.isLoggedIn, false)
        XCTAssertNil(loaded?.predictFiveHourCost)
        XCTAssertNil(loaded?.predictSevenDayCost)
    }

    // MARK: - History Points Preserved

    func testSaveAndLoad_multipleHistoryPoints() {
        let base = Date(timeIntervalSince1970: 1740000000)
        let history = (0..<5).map { i in
            HistoryPoint(
                timestamp: base.addingTimeInterval(Double(i) * 600),
                percent: Double(i) * 10.0
            )
        }
        let snapshot = UsageSnapshot(
            timestamp: base,
            fiveHourPercent: 40.0,
            sevenDayPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: history,
            sevenDayHistory: [],
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        SnapshotStore.save(snapshot, to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHourHistory.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(loaded?.fiveHourHistory[i].percent, Double(i) * 10.0)
        }
    }

    // MARK: - Overwrite

    func testSave_overwritesPreviousFile() {
        let snap1 = UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 1740000000),
            fiveHourPercent: 10.0,
            sevenDayPercent: 5.0,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )
        SnapshotStore.save(snap1, to: tempURL)

        let snap2 = UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 1740000000),
            fiveHourPercent: 99.9,
            sevenDayPercent: 88.8,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: false,
            predictFiveHourCost: 1.0,
            predictSevenDayCost: 2.0
        )
        SnapshotStore.save(snap2, to: tempURL)

        let loaded = SnapshotStore.load(from: tempURL)
        XCTAssertEqual(loaded?.fiveHourPercent, 99.9,
                       "Second save should overwrite first")
        XCTAssertEqual(loaded?.sevenDayPercent, 88.8)
        XCTAssertFalse(loaded?.isLoggedIn ?? true)
        XCTAssertEqual(loaded?.predictFiveHourCost, 1.0)
        XCTAssertEqual(loaded?.predictSevenDayCost, 2.0)
    }

    // MARK: - Load failures

    func testLoad_nonexistentFile_returnsNil() {
        let nonexistent = tempDir.appendingPathComponent("does_not_exist.json")
        let loaded = SnapshotStore.load(from: nonexistent)
        XCTAssertNil(loaded)
    }

    func testLoad_corruptFile_returnsNil() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "{ not valid json !!!".data(using: .utf8)!.write(to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)
        XCTAssertNil(loaded)
    }

    func testLoad_emptyFile_returnsNil() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data().write(to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)
        XCTAssertNil(loaded)
    }

    // MARK: - Directory creation

    func testSave_createsDirectoryIfNeeded() {
        let nested = tempDir
            .appendingPathComponent("a/b/c", isDirectory: true)
            .appendingPathComponent("snapshot.json")

        let snapshot = UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 1740000000),
            fiveHourPercent: 1.0,
            sevenDayPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )
        SnapshotStore.save(snapshot, to: nested)

        let loaded = SnapshotStore.load(from: nested)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHourPercent, 1.0)
    }

    // MARK: - App Group availability

    func testAppGroupSnapshotURL_isNotNil() {
        // Verify App Group container is accessible (does not write any data)
        XCTAssertNotNil(AppGroupConfig.snapshotURL,
                        "App Group snapshot URL should be available")
    }

    // MARK: - Large history (realistic 7-day data)

    func testSaveAndLoad_largeHistory_1300Points() {
        let base = Date(timeIntervalSince1970: 1740000000)
        let history = (0..<1300).map { i in
            HistoryPoint(
                timestamp: base.addingTimeInterval(Double(i) * 300),
                percent: Double(i % 100)
            )
        }
        let snapshot = UsageSnapshot(
            timestamp: base,
            fiveHourPercent: 50.0,
            sevenDayPercent: 74.0,
            fiveHourResetsAt: base.addingTimeInterval(3 * 3600),
            sevenDayResetsAt: base.addingTimeInterval(3 * 24 * 3600),
            fiveHourHistory: Array(history.suffix(300)),
            sevenDayHistory: history,
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        SnapshotStore.save(snapshot, to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHourHistory.count, 300)
        XCTAssertEqual(loaded?.sevenDayHistory.count, 1300)
        XCTAssertEqual(loaded?.fiveHourPercent, 50.0)
        XCTAssertEqual(loaded?.sevenDayPercent, 74.0)
    }

    // MARK: - Integer percent values (API returns integers like 19, not 19.0)

    func testLoad_integerPercentValues() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let json = """
        {
            "timestamp": "2026-02-24T06:04:30Z",
            "fiveHourPercent": 19,
            "sevenDayPercent": 74,
            "fiveHourResetsAt": "2026-02-24T10:00:01Z",
            "sevenDayResetsAt": "2026-02-27T08:00:00Z",
            "fiveHourHistory": [
                {"percent": 9, "timestamp": "2026-02-24T01:04:58Z"},
                {"percent": 19, "timestamp": "2026-02-24T06:04:30Z"}
            ],
            "sevenDayHistory": [
                {"percent": 6, "timestamp": "2026-02-20T18:16:38Z"},
                {"percent": 74, "timestamp": "2026-02-24T06:04:30Z"}
            ],
            "isLoggedIn": true
        }
        """
        try json.data(using: .utf8)!.write(to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded, "Should decode JSON with integer percent values")
        XCTAssertEqual(loaded?.fiveHourPercent, 19.0)
        XCTAssertEqual(loaded?.sevenDayPercent, 74.0)
        XCTAssertEqual(loaded?.fiveHourHistory.count, 2)
        XCTAssertEqual(loaded?.fiveHourHistory[0].percent, 9.0)
        XCTAssertTrue(loaded?.isLoggedIn ?? false)
        XCTAssertNotNil(loaded?.fiveHourResetsAt)
        XCTAssertNotNil(loaded?.sevenDayResetsAt)
    }

    // MARK: - Atomic write safety

    func testSave_atomicWrite_fileExistsAfterSave() {
        let snapshot = UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 1740000000),
            fiveHourPercent: 10.0,
            sevenDayPercent: 5.0,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )
        SnapshotStore.save(snapshot, to: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path),
                       "File should exist after save")
    }

    // MARK: - Timestamp precision

    func testSaveAndLoad_timestampPrecision_secondLevel() {
        let now = Date(timeIntervalSince1970: 1740000000.789)
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: nil,
            sevenDayPercent: nil,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: nil,
            fiveHourHistory: [HistoryPoint(timestamp: now, percent: 10.0)],
            sevenDayHistory: [],
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        SnapshotStore.save(snapshot, to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded)
        // iso8601 drops fractional seconds — verify precision is within 1 second
        XCTAssertEqual(loaded!.timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(loaded!.fiveHourHistory[0].timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(loaded!.fiveHourResetsAt!.timeIntervalSince1970,
                       now.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Widget reads what app writes

    func testWidgetReadPath_loadReturnsDecodableSnapshot() {
        let now = Date(timeIntervalSince1970: 1740000000)
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 19.0,
            sevenDayPercent: 74.0,
            fiveHourResetsAt: now.addingTimeInterval(4 * 3600),
            sevenDayResetsAt: now.addingTimeInterval(3 * 24 * 3600),
            fiveHourHistory: (0..<300).map { i in
                HistoryPoint(timestamp: now.addingTimeInterval(Double(i) * -60), percent: Double(i % 50))
            },
            sevenDayHistory: (0..<1300).map { i in
                HistoryPoint(timestamp: now.addingTimeInterval(Double(i) * -360), percent: Double(i % 100))
            },
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        SnapshotStore.save(snapshot, to: tempURL)
        let loaded = SnapshotStore.load(from: tempURL)

        XCTAssertNotNil(loaded, "Widget must be able to load the snapshot")
        XCTAssertEqual(loaded!.fiveHourPercent, 19.0)
        XCTAssertEqual(loaded!.sevenDayPercent, 74.0)
        XCTAssertTrue(loaded!.isLoggedIn)
        XCTAssertEqual(loaded!.fiveHourHistory.count, 300)
        XCTAssertEqual(loaded!.sevenDayHistory.count, 1300)
        XCTAssertNotNil(loaded!.fiveHourResetsAt)
        XCTAssertNotNil(loaded!.sevenDayResetsAt)
    }
}
