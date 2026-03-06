# NotificationManagerTests.swift

- **path**: `tests/ClaudeUsageTrackerTests/data/NotificationManagerTests.swift`
- **lines**: 58
- **criteria**: S7 (hand-written mock with manual thread safety)

## S7: MockNotificationSender

`MockNotificationSender` (defined in `meta/ViewModelTestDoubles.swift`) is a hand-written mock implementing `NotificationSending`. It uses manual `NSLock` for thread safety around `_sendRecords` and `_requestAuthorizationCallCount`.

The test file itself tests the mock's recording behavior (not production logic). This is a sign the mock is complex enough to warrant its own tests, which suggests it could be replaced by a simpler generated/protocol-based test double.
