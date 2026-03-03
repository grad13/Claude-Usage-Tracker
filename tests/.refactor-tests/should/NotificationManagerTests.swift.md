# NotificationManagerTests.swift - Refactor Analysis

## Issue: S6 - Multiple Modules Tested in Single File

### Location
- Mock tests: lines 13-49 (MockNotificationSender)
- Real implementation tests: lines 51-57 (DefaultNotificationSender)

### Details
This test file tests two distinct modules:
1. **MockNotificationSender** - Mock implementation for testing (5 test cases)
2. **DefaultNotificationSender** - Real NotificationSending protocol implementation (1 test case)

### Recommendation
Split into two separate test files:
- `MockNotificationSenderTests.swift` - Tests for mock behavior (recording, call counting)
- `DefaultNotificationSenderTests.swift` or `NotificationSendingProtocolTests.swift` - Tests for real implementation conformance

### Rationale
- Clear separation of concerns (mock validation vs. real implementation)
- Easier to manage test organization
- Mock tests are internal validation; real tests are contract verification
- Each file has a single, clear purpose
