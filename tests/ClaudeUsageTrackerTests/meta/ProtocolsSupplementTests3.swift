// meta: updated=2026-03-06 14:45 checked=-
// Supplement for: tests/ClaudeUsageTrackerTests/meta/ProtocolsSupplementTests2.swift
// Source spec: spec/meta/protocols.md
// Generated: 2026-03-06
//
// Covers:
//   - DI-03: DefaultSnapshotWriter conforms to SnapshotWriting
//   - DI-07: TokenStore conforms to TokenSyncing
//   - DI-09: DefaultNotificationSender conforms to NotificationSending
//   - DI-10: UsageViewModel conforms to WebViewCoordinatorDelegate
//
// Not covered (source type absent):
//   - DI-03: DefaultSnapshotWriter / SnapshotWriting — neither the protocol nor the
//            struct exist in the codebase at time of generation. Spec defines
//            `struct DefaultSnapshotWriter: SnapshotWriting` delegating to
//            SnapshotStore static methods. Add tests when the type is introduced.
//   - DI-07: TokenSyncing — protocol does not exist in the codebase at time of
//            generation. Spec defines `protocol TokenSyncing: Sendable` with
//            `TokenStore` conforming via extension. Add tests when introduced.

import XCTest
@testable import ClaudeUsageTracker

// MARK: - DI-09: DefaultNotificationSender conforms to NotificationSending

final class NotificationSendingConformanceTests: XCTestCase {

    func test_defaultNotificationSender_conformsToNotificationSending() {
        let sender = DefaultNotificationSender()
        XCTAssertTrue(sender is NotificationSending)
    }

    func test_defaultNotificationSender_isAssignableToNotificationSending() {
        let sender = DefaultNotificationSender()
        let _: any NotificationSending = sender
    }
}

// MARK: - DI-10: UsageViewModel conforms to WebViewCoordinatorDelegate

final class WebViewCoordinatorDelegateConformanceTests: XCTestCase {

    @MainActor
    func test_usageViewModel_conformsToWebViewCoordinatorDelegate() {
        let vm = ViewModelTestFactory.makeVM()
        XCTAssertTrue(vm is WebViewCoordinatorDelegate)
    }

    @MainActor
    func test_usageViewModel_isAssignableToWebViewCoordinatorDelegate() {
        let vm = ViewModelTestFactory.makeVM()
        let _: any WebViewCoordinatorDelegate = vm
    }
}
