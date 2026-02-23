import XCTest
import WeatherCCShared

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
            isLoggedIn: true,
            predictFiveHourCost: 1.23,
            predictSevenDayCost: 4.56
        )

        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.fiveHourPercent, 42.5)
        XCTAssertEqual(decoded.sevenDayPercent, 18.2)
        XCTAssertEqual(decoded.fiveHourHistory.count, 1)
        XCTAssertEqual(decoded.sevenDayHistory.count, 1)
        XCTAssertTrue(decoded.isLoggedIn)
        XCTAssertEqual(decoded.predictFiveHourCost, 1.23)
        XCTAssertEqual(decoded.predictSevenDayCost, 4.56)
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
            isLoggedIn: false,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertNil(decoded.fiveHourPercent)
        XCTAssertNil(decoded.sevenDayPercent)
        XCTAssertNil(decoded.fiveHourResetsAt)
        XCTAssertNil(decoded.sevenDayResetsAt)
        XCTAssertEqual(decoded.fiveHourHistory.count, 0)
        XCTAssertFalse(decoded.isLoggedIn)
        XCTAssertNil(decoded.predictFiveHourCost)
    }

    func testHistoryPointRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1740000000)
        let point = HistoryPoint(timestamp: now, percent: 55.5)

        let data = try makeEncoder().encode(point)
        let decoded = try makeDecoder().decode(HistoryPoint.self, from: data)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.percent, 55.5)
    }

    func testBackwardCompatibility() throws {
        // JSON without predict fields (simulating old format)
        let json = """
        {
            "timestamp": "2026-02-20T00:00:00Z",
            "fiveHourPercent": 10.0,
            "sevenDayPercent": 20.0,
            "fiveHourHistory": [],
            "sevenDayHistory": [],
            "isLoggedIn": true
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.fiveHourPercent, 10.0)
        XCTAssertEqual(decoded.sevenDayPercent, 20.0)
        XCTAssertTrue(decoded.isLoggedIn)
        XCTAssertNil(decoded.predictFiveHourCost)
        XCTAssertNil(decoded.predictSevenDayCost)
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
        XCTAssertNil(p.predictFiveHourCost)
        XCTAssertNil(p.predictSevenDayCost)
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
            isLoggedIn: true,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )

        let data = try makeEncoder().encode(snapshot)
        let decoded = try makeDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.fiveHourHistory.count, 500)
        XCTAssertEqual(decoded.sevenDayHistory.count, 500)
        XCTAssertEqual(decoded.fiveHourHistory[0].percent, 0.0, accuracy: 0.01)
        XCTAssertEqual(decoded.fiveHourHistory[499].percent, 99.8, accuracy: 0.01)
    }
}
