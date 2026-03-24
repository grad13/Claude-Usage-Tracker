// meta: updated=2026-03-04 15:41 checked=-
// Supplement for: tests/ClaudeUsageTrackerTests/meta/ProtocolsSupplementTests.swift
// Source spec: spec/meta/protocols.md
// Generated: 2026-03-04
//
// Covers:
//   - DI-04: DefaultUsageFetcher conforms to UsageFetching
//   - DI-05: DefaultWidgetReloader conforms to WidgetReloading
//   - DI-06: DefaultLoginItemManager conforms to LoginItemManaging
//   - DI-08: DefaultAlertChecker conforms to AlertChecking
//   - EX-01: setEnabled(true) throws on failure
//   - EX-02: setEnabled(false) throws on failure

import XCTest
@testable import ClaudeUsageTracker

// MARK: - DI-04: DefaultUsageFetcher conforms to UsageFetching

final class UsageFetchingConformanceTests: XCTestCase {

    func test_defaultUsageFetcher_isAssignableToUsageFetching() {
        let fetcher = DefaultUsageFetcher()
        let _: any UsageFetching = fetcher
    }

    func test_defaultUsageFetcher_conformsToUsageFetching() {
        let fetcher = DefaultUsageFetcher()
        XCTAssertTrue(fetcher is UsageFetching)
    }
}

// MARK: - DI-05: DefaultWidgetReloader conforms to WidgetReloading

final class WidgetReloadingConformanceTests: XCTestCase {

    func test_defaultWidgetReloader_isAssignableToWidgetReloading() {
        let reloader = DefaultWidgetReloader()
        let _: any WidgetReloading = reloader
    }

    func test_defaultWidgetReloader_conformsToWidgetReloading() {
        let reloader = DefaultWidgetReloader()
        XCTAssertTrue(reloader is WidgetReloading)
    }
}

// MARK: - DI-06: DefaultLoginItemManager conforms to LoginItemManaging

final class LoginItemManagingConformanceTests: XCTestCase {

    func test_defaultLoginItemManager_isAssignableToLoginItemManaging() {
        let manager = DefaultLoginItemManager()
        let _: any LoginItemManaging = manager
    }

    func test_defaultLoginItemManager_conformsToLoginItemManaging() {
        let manager = DefaultLoginItemManager()
        XCTAssertTrue(manager is LoginItemManaging)
    }
}

// MARK: - DI-08: DefaultAlertChecker conforms to AlertChecking

final class AlertCheckingConformanceTests: XCTestCase {

    func test_defaultAlertChecker_isAssignableToAlertChecking() {
        let checker = DefaultAlertChecker()
        let _: any AlertChecking = checker
    }

    func test_defaultAlertChecker_conformsToAlertChecking() {
        let checker = DefaultAlertChecker()
        XCTAssertTrue(checker is AlertChecking)
    }
}

// MARK: - EX-01 / EX-02: LoginItemManaging.setEnabled throws on failure

final class LoginItemManagingThrowsTests: XCTestCase {

    // Uses InMemoryLoginItemManager from ViewModelTestDoubles.swift

    /// EX-01: setEnabled(true) throws when register fails
    func test_setEnabled_true_throwsOnFailure() {
        let manager = InMemoryLoginItemManager()
        let expectedError = NSError(domain: "TestError", code: 1, userInfo: nil)
        manager.shouldThrow = expectedError

        XCTAssertThrowsError(try manager.setEnabled(true)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "TestError")
            XCTAssertEqual(nsError.code, 1)
        }
    }

    /// EX-02: setEnabled(false) throws when unregister fails
    func test_setEnabled_false_throwsOnFailure() {
        let manager = InMemoryLoginItemManager()
        let expectedError = NSError(domain: "TestError", code: 2, userInfo: nil)
        manager.shouldThrow = expectedError

        XCTAssertThrowsError(try manager.setEnabled(false)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "TestError")
            XCTAssertEqual(nsError.code, 2)
        }
    }

    /// EX-01 complement: setEnabled(true) does not throw when shouldThrow is nil
    func test_setEnabled_true_doesNotThrowOnSuccess() {
        let manager = InMemoryLoginItemManager()
        XCTAssertNoThrow(try manager.setEnabled(true))
        XCTAssertEqual(manager.enabledCallCount, 1)
    }

    /// EX-02 complement: setEnabled(false) does not throw when shouldThrow is nil
    func test_setEnabled_false_doesNotThrowOnSuccess() {
        let manager = InMemoryLoginItemManager()
        XCTAssertNoThrow(try manager.setEnabled(false))
        XCTAssertEqual(manager.disabledCallCount, 1)
    }
}
