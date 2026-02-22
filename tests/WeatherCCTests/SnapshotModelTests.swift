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
}
