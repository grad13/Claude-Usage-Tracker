import XCTest
import ClaudeUsageTrackerShared

final class AppGroupConfigTests: XCTestCase {

    func testGroupId() {
        XCTAssertEqual(AppGroupConfig.groupId, "group.grad13.claudeusagetracker")
    }

    func testAppName() {
        XCTAssertEqual(AppGroupConfig.appName, "ClaudeUsageTracker")
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

    func testSnapshotDBPath_nilWhenContainerIsNil() {
        if AppGroupConfig.containerURL == nil {
            XCTAssertNil(AppGroupConfig.snapshotDBPath,
                         "snapshotDBPath should be nil when containerURL is nil")
        } else {
            let path = AppGroupConfig.snapshotDBPath
            XCTAssertNotNil(path)
            XCTAssertTrue(path!.contains("ClaudeUsageTracker"),
                          "snapshotDBPath should contain app name in path")
            XCTAssertTrue(path!.hasSuffix("snapshot.db"),
                          "snapshotDBPath should end with snapshot.db")
        }
    }

    func testLegacySnapshotURL_nilWhenContainerIsNil() {
        if AppGroupConfig.containerURL == nil {
            XCTAssertNil(AppGroupConfig.legacySnapshotURL,
                         "legacySnapshotURL should be nil when containerURL is nil")
        } else {
            let url = AppGroupConfig.legacySnapshotURL
            XCTAssertNotNil(url)
            XCTAssertTrue(url!.path.hasSuffix("snapshot.json"),
                          "legacySnapshotURL should end with snapshot.json")
        }
    }
}
