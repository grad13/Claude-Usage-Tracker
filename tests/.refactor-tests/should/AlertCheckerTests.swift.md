# AlertCheckerTests.swift Refactor Report

## Issue
**S6** (Multiple modules in single test file) + **S7** (Hand-written mock objects)

### Details

#### S6: Multiple Modules
This file tests 3 distinct components:
1. **AlertChecker** (main module under test)
2. **MockNotificationSender** (mock dependency)
3. **InMemoryUsageStore** (mock dependency)

Decision table coverage (spec/data/alert.md):
- Weekly Alert: WA-01 to WA-07 (7 cases)
- Hourly Alert: HA-01 to HA-07 (7 cases)
- Daily Alert: DA-01 to DA-10 + edge case (11 cases)
- Notification Content: 2 cases
- Both alerts simultaneously: 1 case
- Threshold boundary: 2 cases

**Total: 30 test methods covering 3 independent alert types**

#### S7: Hand-Written Mocks
- `MockNotificationSender` (line 8) - external mock, not protocol conformance
- `InMemoryUsageStore` (line 9) - external mock, not protocol conformance

## Recommendation

**Separate into focused test files:**
1. `AlertCheckerTests.swift` — Weekly + Hourly + Daily alert logic (AlertChecker under test)
2. `MockNotificationSenderTests.swift` — NotificationSender mock verification (if needed)
3. `InMemoryUsageStoreTests.swift` — UsageStore mock verification (if needed)

**OR collapse mocks into a single `AlertCheckerTestMocks.swift` file** to keep alert logic tests together while centralizing mock definitions.

Prefer option 1 for clarity: each test file focuses on one module.

## Files Involved
- `AlertChecker` (source)
- `MockNotificationSender` (external, likely in test support)
- `InMemoryUsageStore` (external, likely in test support)
- `UsageResult`, `AppSettings`, `DailyAlertDefinition` (data models)
