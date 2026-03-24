// meta: updated=2026-03-14 11:31 checked=-
import XCTest
import ClaudeUsageTrackerShared

final class SnapshotModelTests: XCTestCase {

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testCodableRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1740000000) // fixed timestamp
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 42.5,
            sevenDayPercent: 18.2,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(86400),
            fiveHourHistory: [HistoryPoint(timestamp: now, percent: 42.5)],
            sevenDayHistory: [HistoryPoint(timestamp: now, percent: 18.2)],
            isLoggedIn: true
        )

        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.fiveHourPercent, 42.5)
        XCTAssertEqual(decoded.sevenDayPercent, 18.2)
        XCTAssertEqual(decoded.fiveHourHistory.count, 1)
        XCTAssertEqual(decoded.sevenDayHistory.count, 1)
        XCTAssertTrue(decoded.isLoggedIn)
    }

    func testCodableWithNils() throws {
        let now = Date(timeIntervalSince1970: 1740000000)
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: nil,
            sevenDayPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: false
        )

        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertNil(decoded.fiveHourPercent)
        XCTAssertNil(decoded.sevenDayPercent)
        XCTAssertNil(decoded.fiveHourResetsAt)
        XCTAssertNil(decoded.sevenDayResetsAt)
        XCTAssertEqual(decoded.fiveHourHistory.count, 0)
        XCTAssertFalse(decoded.isLoggedIn)
    }

    func testHistoryPointRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1740000000)
        let point = HistoryPoint(timestamp: now, percent: 55.5)

        let data = try makeEncoder().encode(point)
        let decoded = try makeDecoder().decode(HistoryPoint.self, from: data)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.percent, 55.5)
    }

    // MARK: - Placeholder

    func testPlaceholder_hasExpectedValues() {
        let p = UsageSnapshot.placeholder
        XCTAssertEqual(p.fiveHourPercent, 45.0)
        XCTAssertEqual(p.sevenDayPercent, 20.0)
        XCTAssertTrue(p.isLoggedIn)
        XCTAssertNotNil(p.fiveHourResetsAt)
        XCTAssertNotNil(p.sevenDayResetsAt)
        XCTAssertEqual(p.fiveHourHistory.count, 0)
        XCTAssertEqual(p.sevenDayHistory.count, 0)
    }

    // MARK: - Forward Compatibility (extra unknown keys ignored)

    func testForwardCompatibility_extraKeysIgnored() throws {
        let json = """
        {
            "timestamp": "2026-02-20T00:00:00Z",
            "fiveHourPercent": 10.0,
            "sevenDayPercent": 20.0,
            "fiveHourHistory": [],
            "sevenDayHistory": [],
            "isLoggedIn": true,
            "futureField": "should be ignored",
            "anotherNew": 42
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.fiveHourPercent, 10.0,
                       "Extra unknown keys should be silently ignored by Codable")
    }

    // MARK: - HistoryPoint extreme values

    func testHistoryPointExtremeValues() throws {
        let now = Date(timeIntervalSince1970: 1740000000)
        // Negative and >100 percent
        let points = [
            HistoryPoint(timestamp: now, percent: -10.0),
            HistoryPoint(timestamp: now, percent: 0.0),
            HistoryPoint(timestamp: now, percent: 100.0),
            HistoryPoint(timestamp: now, percent: 200.0),
        ]

        for point in points {
            let data = try makeEncoder().encode(point)
            let decoded = try makeDecoder().decode(HistoryPoint.self, from: data)
            XCTAssertEqual(decoded.percent, point.percent, accuracy: 0.01,
                           "HistoryPoint with percent=\(point.percent) should round-trip")
        }
    }

    // MARK: - Missing required field

    func testMissingRequiredField_throws() {
        // JSON missing "isLoggedIn" (required, non-optional)
        let json = """
        {
            "timestamp": "2026-02-20T00:00:00Z",
            "fiveHourHistory": [],
            "sevenDayHistory": []
        }
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try makeDecoder().decode(UsageSnapshot.self, from: data),
                             "Missing required field 'isLoggedIn' should throw")
    }

    // MARK: - Placeholder resetsAt timing

    func testPlaceholder_resetsAtInFuture() {
        let p = UsageSnapshot.placeholder
        let now = Date()
        // placeholder sets fiveHourResetsAt = Date().addingTimeInterval(2.5 * 3600)
        // and sevenDayResetsAt = Date().addingTimeInterval(3.5 * 24 * 3600)
        XCTAssertGreaterThan(p.fiveHourResetsAt!.timeIntervalSince(now), 0,
                             "fiveHourResetsAt should be in the future")
        XCTAssertGreaterThan(p.sevenDayResetsAt!.timeIntervalSince(now), 0,
                             "sevenDayResetsAt should be in the future")
    }

    // MARK: - UsageReader (file I/O round-trip)

    func testUsageReader_loadFromFile() throws {
        guard let url = AppGroupConfig.snapshotURL else { return }
        // Ensure directory exists
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1740000000)
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 42.5,
            sevenDayPercent: 18.2,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            sevenDayResetsAt: now.addingTimeInterval(86400),
            fiveHourHistory: [HistoryPoint(timestamp: now, percent: 42.5)],
            sevenDayHistory: [HistoryPoint(timestamp: now, percent: 18.2)],
            isLoggedIn: true
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)

        let loaded = UsageReader.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHourPercent, 42.5)
        XCTAssertEqual(loaded?.sevenDayPercent, 18.2)
        XCTAssertTrue(loaded?.isLoggedIn == true)
        XCTAssertEqual(loaded?.fiveHourHistory.count, 1)

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    func testUsageReader_noData_returnsNil() {
        guard let url = AppGroupConfig.snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)

        let loaded = UsageReader.load()
        XCTAssertNil(loaded, "UsageReader should return nil when no snapshot file exists")
    }

    func testUsageReader_corruptData_returnsNil() throws {
        guard let url = AppGroupConfig.snapshotURL else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not valid json".data(using: .utf8)!.write(to: url, options: .atomic)

        let loaded = UsageReader.load()
        XCTAssertNil(loaded, "UsageReader should return nil for corrupt data")

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Large history array round-trip

    func testCodableWithManyHistoryPoints() throws {
        let now = Date(timeIntervalSince1970: 1740000000)
        let points = (0..<500).map { i in
            HistoryPoint(timestamp: now.addingTimeInterval(Double(i) * 60), percent: Double(i) * 0.2)
        }
        let snapshot = UsageSnapshot(
            timestamp: now,
            fiveHourPercent: 50.0,
            sevenDayPercent: 25.0,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: points,
            sevenDayHistory: points,
            isLoggedIn: true
        )

        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.fiveHourHistory.count, 500)
        XCTAssertEqual(decoded.sevenDayHistory.count, 500)
        XCTAssertEqual(decoded.fiveHourHistory[0].percent, 0.0, accuracy: 0.01)
        XCTAssertEqual(decoded.fiveHourHistory[499].percent, 99.8, accuracy: 0.01)
    }
}
