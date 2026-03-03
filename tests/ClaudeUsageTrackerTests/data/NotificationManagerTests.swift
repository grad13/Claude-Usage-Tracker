import XCTest
@testable import ClaudeUsageTracker

/// Tests for MockNotificationSender (verifying mock recording behavior)
/// and NotificationSending protocol conformance.
///
/// Note: NotificationManager uses UNUserNotificationCenter directly,
/// which cannot be tested in unit tests. Integration testing is done
/// via real device verification. These tests verify the mock captures
/// calls correctly, which is the foundation for AlertChecker tests.
final class NotificationManagerTests: XCTestCase {

    // MARK: - MockNotificationSender

    func testMockSend_recordsTitleBodyIdentifier() async {
        let mock = MockNotificationSender()

        await mock.send(title: "Test Title", body: "Test Body", identifier: "test-id")

        XCTAssertEqual(mock.sendRecords.count, 1)
        XCTAssertEqual(mock.sendRecords[0].title, "Test Title")
        XCTAssertEqual(mock.sendRecords[0].body, "Test Body")
        XCTAssertEqual(mock.sendRecords[0].identifier, "test-id")
    }

    func testMockSend_multipleCallsRecordAll() async {
        let mock = MockNotificationSender()

        await mock.send(title: "A", body: "B", identifier: "id-1")
        await mock.send(title: "C", body: "D", identifier: "id-2")

        XCTAssertEqual(mock.sendRecords.count, 2)
        XCTAssertEqual(mock.sendRecords[0].identifier, "id-1")
        XCTAssertEqual(mock.sendRecords[1].identifier, "id-2")
    }

    func testMockRequestAuthorization_returnsConfiguredValue() async {
        let mock = MockNotificationSender()

        mock.authorizationResult = true
        let granted = await mock.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 1)

        mock.authorizationResult = false
        let denied = await mock.requestAuthorization()
        XCTAssertFalse(denied)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 2)
    }

    // MARK: - DefaultNotificationSender conformance

    func testDefaultNotificationSender_conformsToProtocol() {
        // Verify DefaultNotificationSender can be created and conforms to NotificationSending
        let sender: any NotificationSending = DefaultNotificationSender()
        XCTAssertNotNil(sender)
    }
}
