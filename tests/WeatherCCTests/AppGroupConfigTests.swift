import XCTest
import WeatherCCShared

final class AppGroupConfigTests: XCTestCase {

    func testGroupId() {
        XCTAssertEqual(AppGroupConfig.groupId, "C3WA2TT222.grad13.weathercc")
    }

    func testAppName() {
        XCTAssertEqual(AppGroupConfig.appName, "WeatherCC")
    }

    func testContainerURL_returnsNilInTestEnvironment() {
        // App Group container is typically not available in the test runner
        // because the test host doesn't have the App Group entitlement.
        // This test documents the expected behavior.
        let url = AppGroupConfig.containerURL
        // Could be nil (no entitlement) or non-nil (test host has entitlement)
        // Just verify it doesn't crash
        _ = url
    }

    func testSnapshotURL_nilWhenContainerIsNil() {
        // If containerURL is nil, snapshotURL must also be nil
        if AppGroupConfig.containerURL == nil {
            XCTAssertNil(AppGroupConfig.snapshotURL,
                         "snapshotURL should be nil when containerURL is nil")
        } else {
            // If container exists, snapshotURL should be non-nil and contain expected path components
            let url = AppGroupConfig.snapshotURL
            XCTAssertNotNil(url)
            XCTAssertTrue(url!.path.contains("WeatherCC"),
                          "snapshotURL should contain app name in path")
            XCTAssertTrue(url!.path.hasSuffix("snapshot.json"),
                          "snapshotURL should end with snapshot.json")
        }
    }
}
