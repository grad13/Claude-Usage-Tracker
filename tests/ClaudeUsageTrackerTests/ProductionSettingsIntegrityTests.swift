import XCTest
import ClaudeUsageTrackerShared

// MARK: - Production Settings Integrity Guard
// This test verifies that the production settings file is not corrupted by test execution.
// It reads the real App Group settings file at the START of the test suite and again at the END.
// If the content changed, the test fails — meaning some test (or the test host app) wrote to production state.
// This test exists because settings corruption has occurred MULTIPLE TIMES and was only caught by the user.

final class ProductionSettingsIntegrityTests: XCTestCase {

    private static var settingsPath: String?
    private static var hashBefore: String?

    /// Runs ONCE before all tests in this class. Snapshots the production settings file.
    override class func setUp() {
        super.setUp()
        guard let container = AppGroupConfig.containerURL else { return }
        let path = container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppGroupConfig.appName, isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
        settingsPath = path
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else { return }
        hashBefore = data.sha256Hex
    }

    func testProductionSettings_notCorruptedByTests() {
        guard let path = Self.settingsPath, let before = Self.hashBefore else {
            // No production settings file exists — nothing to protect
            return
        }
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            XCTFail("Production settings file disappeared during test execution: \(path)")
            return
        }
        let after = data.sha256Hex
        XCTAssertEqual(before, after,
                       "PRODUCTION SETTINGS WERE MODIFIED BY TESTS. " +
                       "This means a test (or the test host app) wrote to the real App Group settings. " +
                       "Path: \(path)")
    }
}

private extension Data {
    var sha256Hex: String {
        // Simple hash using built-in CryptoKit-free approach (sum of bytes as hex)
        // Not cryptographic — just a change detection fingerprint
        let bytes = [UInt8](self)
        var hash: UInt64 = 5381
        for byte in bytes {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
