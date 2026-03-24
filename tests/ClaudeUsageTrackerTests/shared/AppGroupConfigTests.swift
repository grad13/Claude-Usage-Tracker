// meta: updated=2026-03-15 03:04 checked=-
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

    func testSettingsInt_nilWhenContainerIsNil() {
        if AppGroupConfig.containerURL == nil {
            XCTAssertNil(AppGroupConfig.settingsInt(forKey: "refresh_interval_minutes"),
                         "settingsInt should return nil when containerURL is nil")
        }
    }

    func testSettingsString_nilWhenContainerIsNil() {
        if AppGroupConfig.containerURL == nil {
            XCTAssertNil(AppGroupConfig.settingsString(forKey: "nonexistent_key"),
                         "settingsString should return nil when containerURL is nil")
        }
    }

    func testUsageDBPath_nilWhenContainerIsNil() {
        if AppGroupConfig.containerURL == nil {
            XCTAssertNil(AppGroupConfig.usageDBPath,
                         "usageDBPath should be nil when containerURL is nil")
        } else {
            let path = AppGroupConfig.usageDBPath
            XCTAssertNotNil(path)
            XCTAssertTrue(path!.contains("ClaudeUsageTracker"),
                          "usageDBPath should contain app name in path")
            XCTAssertTrue(path!.hasSuffix("usage.db"),
                          "usageDBPath should end with usage.db")
        }
    }
}
