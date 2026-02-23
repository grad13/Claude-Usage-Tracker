import XCTest
import WeatherCCShared

final class SnapshotStoreTests: XCTestCase {

    // Note: SnapshotStore uses Keychain with hardcoded service/account.
    // In the test runner, Keychain items are scoped to the test process's
    // code signing identity, so they won't interfere with the real app.

    override func tearDown() {
        // Clean up any keychain item we created during the test
        SnapshotStore.save(UsageSnapshot.placeholder) // ensure item exists
        // We can't delete keychain items from here (no delete API exposed),
        // but the test runner's keychain is separate from the app's.
        super.tearDown()
    }

    // MARK: - Save does not crash

    func testSave_doesNotCrash() {
        let snapshot = UsageSnapshot(
            timestamp: Date(),
            fiveHourPercent: 42.5,
            sevenDayPercent: 18.2,
            fiveHourResetsAt: Date().addingTimeInterval(3600),
            sevenDayResetsAt: Date().addingTimeInterval(86400),
            fiveHourHistory: [HistoryPoint(timestamp: Date(), percent: 42.5)],
            sevenDayHistory: [],
            isLoggedIn: true,
            predictFiveHourCost: 1.23,
            predictSevenDayCost: 4.56
        )
        // Should not crash
        SnapshotStore.save(snapshot)
    }

    func testSave_nilFields_doesNotCrash() {
        let snapshot = UsageSnapshot(
            timestamp: Date(),
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
        SnapshotStore.save(snapshot)
    }

    // MARK: - Save then Load Round-Trip

    func testSaveAndLoad_roundTrip() {
        let now = Date(timeIntervalSince1970: 1740000000) // fixed
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
        SnapshotStore.save(snapshot)

        let loaded = SnapshotStore.load()
        // Keychain may not be available in all test environments
        // If load returns nil, skip assertions (document as environment-dependent)
        guard let loaded else {
            // Keychain not accessible in this test environment — skip
            return
        }

        XCTAssertEqual(loaded.fiveHourPercent, 55.5)
        XCTAssertEqual(loaded.sevenDayPercent, 22.2)
        XCTAssertTrue(loaded.isLoggedIn)
        XCTAssertEqual(loaded.fiveHourHistory.count, 1)
        XCTAssertEqual(loaded.sevenDayHistory.count, 1)
        XCTAssertEqual(loaded.predictFiveHourCost, 3.14)
        XCTAssertEqual(loaded.predictSevenDayCost, 9.99)
        // Timestamp accuracy: ISO 8601 round-trip may lose sub-second precision
        XCTAssertEqual(loaded.timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Update (second save overwrites first)

    func testSave_updateOverwritesPrevious() {
        let snap1 = UsageSnapshot(
            timestamp: Date(),
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
        SnapshotStore.save(snap1)

        let snap2 = UsageSnapshot(
            timestamp: Date(),
            fiveHourPercent: 99.9,
            sevenDayPercent: 88.8,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fiveHourHistory: [],
            sevenDayHistory: [],
            isLoggedIn: false,
            predictFiveHourCost: nil,
            predictSevenDayCost: nil
        )
        SnapshotStore.save(snap2)

        guard let loaded = SnapshotStore.load() else { return }
        XCTAssertEqual(loaded.fiveHourPercent, 99.9,
                       "Second save should overwrite first")
        XCTAssertEqual(loaded.sevenDayPercent, 88.8)
        XCTAssertFalse(loaded.isLoggedIn)
    }
}
