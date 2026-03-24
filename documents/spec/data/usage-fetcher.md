---
updated: 2026-03-16 06:59
checked: -
Deprecated: -
Format: spec-v2.1
Source: code/app/ClaudeUsageTracker/UsageFetcher.swift
---

# Specification: UsageFetcher

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/app/ClaudeUsageTracker/UsageFetcher.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/architecture.md |
| Test Type | Unit |

## UsageResult struct field definitions

Struct returned by `UsageFetcher.parse()`. All fields are optional.

| Field | Type | Description |
|-------|------|-------------|
| `fiveHourPercent` | `Double?` | 5-hour window utilization (%, 0-100) |
| `sevenDayPercent` | `Double?` | 7-day window utilization (%, 0-100) |
| `fiveHourResetsAt` | `Date?` | 5-hour window reset time |
| `sevenDayResetsAt` | `Date?` | 7-day window reset time |
| `fiveHourStatus` | `Int?` | 5-hour window status (0=within_limit, 1=approaching_limit, 2=exceeded_limit) |
| `sevenDayStatus` | `Int?` | 7-day window status (same as above) |
| `fiveHourLimit` | `Double?` | 5-hour window limit (Format B only) |
| `fiveHourRemaining` | `Double?` | 5-hour window remaining (Format B only) |
| `sevenDayLimit` | `Double?` | 7-day window limit (Format B only) |
| `sevenDayRemaining` | `Double?` | 7-day window remaining (Format B only) |
| `rawJSON` | `String?` | Raw JSON string from API response (for debugging/logging) |

## UsageFetchError error type

Error type thrown by `UsageFetcher`. Conforms to `LocalizedError`.

| Case | Parameters | Description |
|------|------------|-------------|
| `scriptFailed(String)` | error message | JS script execution failure, HTTP error, org ID retrieval failure |
| `decodingFailed` | none | JSON decode failure (raw is not a String, UTF-8 conversion failure) |

### isAuthError property

Computed property on `UsageFetchError`. Determines whether the error is authentication-related.

- For `scriptFailed`: returns `true` if the lowercased message contains any of:
  - `"missing organization"`
  - `"http 401"`
  - `"http 403"`
- For `decodingFailed`: always `false`

Used by `UsageViewModel` as the criterion for setting `isAutoRefreshEnabled` to `false`.

## hasValidSession function

`UsageFetcher.hasValidSession(using:)` -- determines session validity via cookies.

- **Signature**: `@MainActor static func hasValidSession(using webView: WKWebView) async -> Bool`
- **Criteria**: A cookie must exist in the Cookie Store satisfying all of:
  - `name == "sessionKey"`
  - `domain` ends with `.claude.ai`
  - `expiresDate` is in the future (if `expiresDate` is nil, the cookie is treated as a valid session cookie)
- **Debug logging**: Logs total cookie count, claude.ai cookie count via NSLog. When session is invalid, also logs the list of claude.ai cookie names

## Format A/B dual-format parsing

### Format A (current API)

```json
{
  "five_hour": {
    "utilization": 25,
    "resets_at": "2026-02-26T12:00:00.000Z",
    "status": "within_limit"
  },
  "seven_day": {
    "utilization": 60,
    "resets_at": "2026-03-01T00:00:00.000Z",
    "status": "approaching_limit"
  }
}
```

- Top-level keys: `five_hour`, `seven_day`
- Utilization: `utilization` field (direct percentage value)
- Reset time: `resets_at` (ISO 8601 string)
- Status: `status` string converted to Int via `parseStatus`

### Format B (legacy format from documentation)

```json
{
  "windows": {
    "5h": {
      "limit": 100,
      "remaining": 75,
      "resets_at": 1740000000
    },
    "7d": {
      "limit": 500,
      "remaining": 200,
      "resets_at": 1740500000
    }
  }
}
```

- Top-level keys: `windows` > `5h`, `7d`
- Utilization: calculated as `(limit - remaining) / limit * 100` via `calcPercent`
- Reset time: `resets_at` (Unix timestamp in seconds)
- `limit` and `remaining` fields are only stored in `UsageResult` for Format B

### Parse selection logic

```
Does json["windows"] exist?
  -> YES: Format B (windows["5h"], windows["7d"])
  -> NO:  Format A (json["five_hour"], json["seven_day"])
```

### Error response

Errors caught by the JS script are returned as `{"__error": "error message"}`. `parse()` checks for the `__error` key first and throws `UsageFetchError.scriptFailed` if present.

## Debug logging

`fetch()` records the API response in two locations:

1. **NSLog**: `[ClaudeUsageTracker] API response: {JSON}` -- viewable in Console.app
2. **File log**: Appended to `$TMPDIR/ClaudeUsageTracker-debug.log` with ISO 8601 timestamp via `UsageViewModel.debug()`. An empty file is created at launch (`"".write(to:)`), and subsequent entries are appended via `FileHandle.seekToEndOfFile()`. File logging uses `try?` to silently ignore failures.

## ISO 8601 legacy parsing (3-stage fallback)

`parseResetDate(_:)` parses an ISO 8601 string through 3 stages:

1. **With fractional seconds**: `ISO8601DateFormatter` (`.withInternetDateTime, .withFractionalSeconds`)
   - Example: `"2026-02-26T12:00:00.000Z"`
2. **Without fractional seconds**: `ISO8601DateFormatter` (`.withInternetDateTime`)
   - Example: `"2026-02-26T12:00:00Z"`
3. **Trim high-precision fractional seconds**: If fractional digits exceed 3, trim to 3 digits and re-parse
   - Example: `"2026-02-26T12:00:00.123456Z"` -> `"2026-02-26T12:00:00.123Z"` -> parse

`trimFractionalSeconds(_:)` extracts the fractional portion between `.` and `Z`/`+`/`-`, trimming to 3 digits if 4 or more are present. Returns `nil` if 3 or fewer digits (indicating no trimming needed).

`parseResetsAt(_:)` integrates these and accepts both numeric (Unix timestamp) and string (ISO 8601) values:
- `Double` or `Int` -> `Date(timeIntervalSince1970:)`
- `String` -> `parseResetDate()`

## Org ID retrieval within JS (4-stage fallback)

1. **Stage 1: `document.cookie`** -- extracts the `lastActiveOrg` cookie via regex
2. **Stage 2: Performance API** -- searches resource URLs from `performance.getEntriesByType("resource")` in reverse order for the `/api/organizations/{UUID}/` pattern
3. **Stage 3: HTML content** -- searches `document.documentElement.innerHTML` for the same UUID pattern via regex
4. **Stage 4: `/api/organizations` API** -- calls `fetch("https://claude.ai/api/organizations")` and uses the `uuid` or `id` field from the first element of the response array

The success/failure of each stage is recorded in the `diag` array (e.g., `"S1:OK"`, `"S2:MISS"`, `"S4:HTTP200"`), providing diagnostic information via errors or the `__diag` field in the response.

When all stages fail: `Error("Missing organization id [S1:MISS(...),S2:MISS,S3:MISS,S4:...]")` is thrown and converted to `UsageFetchError.scriptFailed` on the Swift side.

## parsePercent / calcPercent helpers

**`parsePercent(_:)`** -- extracts utilization from a window dictionary.

- Format A: returns the `utilization` field directly (`Double` or `Int` -> `Double`)
- Format B: falls back to `calcPercent(limit:remaining:)`

**`calcPercent(limit:remaining:)`** -- calculates utilization from limit/remaining.

- Formula: `(limit - remaining) / limit * 100.0`
- Returns `nil` if `limit` is 0 or less, or if `limit`/`remaining` is nil or non-numeric
- Accepts both `Double` and `Int` (`Any` type parameters)

## parseStatus helper

Converts a status string to an Int.

| Input string | Return value |
|-------------|--------------|
| `"within_limit"` | `0` |
| `"approaching_limit"` | `1` |
| `"exceeded_limit"` | `2` |
| Other / `nil` | `nil` |
