# Refactor Should-Haves: ArchitectureSupplementTests.swift

## Summary
- **S6 Violation**: Multiple modules/components tested in single file (UsageViewModel, WebViewCoordinator, CookieChangeObserver, and 8+ supporting classes)
- **S7 Violation**: Hand-written stub/in-memory implementations (StubUsageFetcher, InMemorySettingsStore, etc.) instead of protocol-conformance mocks

## File Details
- **Path**: `tests/ClaudeUsageTrackerTests/ArchitectureSupplementTests.swift`
- **Line Count**: 386 lines
- **Test Classes**: 6 test classes across 5 test suites

## S6: Multiple Modules in Single File

### Issue
The file contains 6 test classes (`ArchitectureDataStoreTests`, `ArchitectureDelegatePlacementTests`, `ArchitectureAutoRefreshFlagTests`, `ArchitectureRedirectCooldownTests`, `ArchitectureSignOutTests`, `ArchitectureCookieObserverTests`) testing distinct architectural concerns:

1. **WebView DataStore structure** (lines 27-76)
   - dataStore persistence, singleton instance

2. **Delegate placement** (lines 83-129)
   - navigationDelegate, uiDelegate setup

3. **Auto-refresh state machine** (lines 138-199)
   - isAutoRefreshEnabled nil/true/false transitions

4. **Redirect cooldown logic** (lines 207-265)
   - 5-second cooldown, canRedirect() logic

5. **Sign-out cleanup** (lines 274-319)
   - isLoggedIn reset, isAutoRefreshEnabled reset

6. **Cookie observation** (lines 326-385)
   - CookieChangeObserver protocol conformance, session detection

### Recommendation
Split into separate test files by architectural concern:
- `ArchitectureWebViewDataStoreTests.swift` (lines 27-76)
- `ArchitectureDelegatePlacementTests.swift` (lines 83-129)
- `ArchitectureAutoRefreshFlagTests.swift` (lines 138-199)
- `ArchitectureRedirectCooldownTests.swift` (lines 207-265)
- `ArchitectureSignOutTests.swift` (lines 274-319)
- `ArchitectureCookieObserverTests.swift` (lines 326-385)

---

## S7: Hand-Written Stubs Instead of Protocol Mocks

### Issue
The test helpers (`makeVM()` across all test classes) use hand-written in-memory implementations instead of protocol-conformance mocks:

**Lines 29-40, 85-96, 140-151, 209-220, 276-287, 335-346:**
```swift
UsageViewModel(
    fetcher: StubUsageFetcher(),
    settingsStore: InMemorySettingsStore(),
    usageStore: InMemoryUsageStore(),
    snapshotWriter: InMemorySnapshotWriter(),
    widgetReloader: InMemoryWidgetReloader(),
    tokenSync: InMemoryTokenSync(),
    loginItemManager: InMemoryLoginItemManager(),
    alertChecker: MockAlertChecker()
)
```

These are custom implementations rather than:
- `StubUsageFetcher` conforming to a `UsageFetcher` protocol with minimal stub behavior
- Similar for all 7+ other dependencies

### Recommendation
For each test dependency, define:
1. Clear protocol (e.g., `protocol UsageFetcher`, `protocol SettingsStore`, etc.)
2. Stub implementation that conforms to protocol with minimal setup
3. Optional: Use `DefaultMockFactory` or similar to reduce boilerplate in `makeVM()`

**Example refactor for ArchitectureRedirectCooldownTests:**
```swift
func makeVM() -> UsageViewModel {
    let factory = DefaultMockFactory()
    return UsageViewModel(
        fetcher: factory.stubUsageFetcher,
        settingsStore: factory.inMemorySettingsStore,
        // ... remaining dependencies
    )
}
```

---

## Impact

- **S6 Impact**: Long file is difficult to navigate; each test class deserves its own focused file
- **S7 Impact**: Boilerplate `makeVM()` repeated 6 times with identical mock setup; shared factory would reduce duplication
