# ViewModelTests.swift — should refactor

- **Category**: S6 (multiple modules in single file)
- **Lines**: 259
- **Location**: `tests/ClaudeUsageTrackerTests/meta/ViewModelTests.swift`

## Reason

Single file tests 6 distinct concerns of `UsageViewModel`:

1. **statusText** (lines 39-63) — display formatting logic
2. **statusText rounding/boundaries** (lines 65-88) — edge cases for formatting
3. **timeProgress** (lines 90-145) — static time calculation method
4. **Computed timeProgress properties** (lines 147-161) — instance-level wrappers
5. **WebView data store + closePopup** (lines 163-195) — WebView configuration and popup management
6. **reloadHistory + Alert integration** (lines 197-259) — store loading and alert checker delegation

## Suggested Split

| New File | MARK sections | Approx lines |
|---|---|---|
| `ViewModelStatusTextTests.swift` | statusText, rounding, boundaries | ~50 |
| `ViewModelTimeProgressTests.swift` | timeProgress (static + computed) | ~70 |
| `ViewModelWebViewTests.swift` | WebView data store, closePopup | ~35 |
| `ViewModelStoreAlertTests.swift` | reloadHistory, Alert integration | ~60 |
