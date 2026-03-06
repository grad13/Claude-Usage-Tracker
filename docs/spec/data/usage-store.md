---
Created: 2026-02-26
Updated: 2026-03-07
Checked: -
Deprecated: -
Format: spec-v2.1
Source: code/ClaudeUsageTracker/UsageStore.swift
---

# Specification: UsageStore

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/ClaudeUsageTracker/UsageStore.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/data/settings.md |
| Test Type | Unit |

## Data Storage

Fetch history is stored in `usage.db` (SQLite) within the App Group container.

| Table | Purpose |
|-------|---------|
| `hourly_sessions` | 5-hour window session management (normalized epoch of resets_at) |
| `weekly_sessions` | 7-day window session management (normalized epoch of resets_at) |
| `usage_log` | Time-series record of fetch results |

```
~/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/{AppGroupConfig.appName}/
├── settings.json   <- User settings (JSON)
└── usage.db        <- Fetch history (SQLite)
```

Note: The App Group ID is `group.grad13.claudeusagetracker` (obtained via `AppGroupConfig`). `AppGroupConfig.appName` is dynamically derived from the build configuration.

## Schema (3 tables)

### hourly_sessions table

```sql
CREATE TABLE IF NOT EXISTS hourly_sessions (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    resets_at INTEGER NOT NULL UNIQUE
);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `id` | INTEGER | NO | Primary key (AUTOINCREMENT) |
| `resets_at` | INTEGER | NO | 5-hour window reset time (epoch seconds, rounded by `normalizeResetsAt()`). UNIQUE constraint |

### weekly_sessions table

```sql
CREATE TABLE IF NOT EXISTS weekly_sessions (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    resets_at INTEGER NOT NULL UNIQUE
);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `id` | INTEGER | NO | Primary key (AUTOINCREMENT) |
| `resets_at` | INTEGER | NO | 7-day window reset time (epoch seconds, rounded by `normalizeResetsAt()`). UNIQUE constraint |

### usage_log table

```sql
CREATE TABLE IF NOT EXISTS usage_log (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp         INTEGER NOT NULL,
    hourly_percent    REAL,
    weekly_percent    REAL,
    hourly_session_id INTEGER REFERENCES hourly_sessions(id),
    weekly_session_id INTEGER REFERENCES weekly_sessions(id),
    CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
);
```

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `id` | INTEGER | NO | Primary key (AUTOINCREMENT) |
| `timestamp` | INTEGER | NO | Record time (epoch seconds) |
| `hourly_percent` | REAL | YES | 5-hour window utilization. CHECK constraint prevents both this and `weekly_percent` from being NULL simultaneously |
| `weekly_percent` | REAL | YES | 7-day window utilization. Same constraint as above |
| `hourly_session_id` | INTEGER | YES | Foreign key to `hourly_sessions(id)` |
| `weekly_session_id` | INTEGER | YES | Foreign key to `weekly_sessions(id)` |

### CHECK constraint

```sql
CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
```

Rejects INSERT of rows where both `hourly_percent` and `weekly_percent` are NULL. Prevents meaningless data from broken parser output from entering the database.

## normalizeResetsAt()

The `resets_at` returned by the API contains millisecond jitter (e.g., `13:59:59.939` / `14:00:00.082`). `normalizeResetsAt()` rounds this to the nearest hour so that the same session maps to the same epoch value.

```swift
func normalizeResetsAt(_ date: Date) -> Int {
    let epoch = Int(date.timeIntervalSince1970)
    return ((epoch + 1800) / 3600) * 3600
}
```

- Input: `Date`
- Output: rounded epoch seconds (`Int`)
- Logic: add 1800 (30 minutes) to the epoch, integer-divide by 3600, multiply by 3600 -> nearest hour

## save() validation

`save(_ result: UsageResult)` validates input with the following guard before INSERT.

```swift
guard result.fiveHourPercent != nil || result.sevenDayPercent != nil else { return }
```

- If both `fiveHourPercent` and `sevenDayPercent` are nil, silently returns (no error output)
- This enforces the same logic as the DB CHECK constraint at the application layer

## save() session management

`save()` creates a session row via `INSERT OR IGNORE` in the corresponding session table when `fiveHourResetsAt` / `sevenDayResetsAt` is non-nil (or retrieves the existing row), and links its `id` as the foreign key in `usage_log`.

```
fiveHourResetsAt -> normalizeResetsAt() -> hourly_sessions.resets_at -> hourly_session_id
sevenDayResetsAt -> normalizeResetsAt() -> weekly_sessions.resets_at -> weekly_session_id
```

## DataPoint struct

`UsageStore.DataPoint` is a nested struct representing a history query result.

```swift
struct DataPoint {
    let timestamp: Date
    let fiveHourPercent: Double?
    let sevenDayPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
}
```

| Property | Type | Description |
|----------|------|-------------|
| `timestamp` | `Date` | Record time (converted from epoch seconds) |
| `fiveHourPercent` | `Double?` | 5-hour window utilization |
| `sevenDayPercent` | `Double?` | 7-day window utilization |
| `fiveHourResetsAt` | `Date?` | 5-hour window reset time (JOINed from `hourly_sessions.resets_at`) |
| `sevenDayResetsAt` | `Date?` | 7-day window reset time (JOINed from `weekly_sessions.resets_at`) |

## Differences between loadAllHistory() and loadHistory(windowSeconds:)

| Aspect | `loadAllHistory()` | `loadHistory(windowSeconds:)` |
|--------|-------------------|-------------------------------|
| Selected columns | `timestamp`, `hourly_percent`, `weekly_percent` + `resets_at` via JOIN | `timestamp`, `hourly_percent`, `weekly_percent` + `resets_at` via JOIN |
| JOIN | `LEFT JOIN hourly_sessions`, `LEFT JOIN weekly_sessions` | `LEFT JOIN hourly_sessions`, `LEFT JOIN weekly_sessions` |
| `resets_at` columns | retrieved | retrieved |
| WHERE clause | none (all rows) | `timestamp >= ?` (from cutoff onward) |
| Sort order | `ORDER BY timestamp ASC` | `ORDER BY timestamp ASC` |
| Return type | `[DataPoint]` (`fiveHourResetsAt`, `sevenDayResetsAt` populated) | `[DataPoint]` (`fiveHourResetsAt`, `sevenDayResetsAt` populated) |
| Use case | Analysis view (full history needed) | Menu bar graph (only recent N seconds needed) |

Both methods use the same JOIN query and `readDataPoints()` helper (code duplication eliminated).

## shared singleton initialization path

`UsageStore.shared` is a lazily initialized singleton via `static let`.

```
Normal environment:
  AppGroupConfig.containerURL
  -> ~/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/{AppGroupConfig.appName}/usage.db

Test environment (DEBUG + XCTestConfigurationFilePath env var present):
  NSTemporaryDirectory()/ClaudeUsageTracker-test-shared/usage.db
```

- In normal environment, if `AppGroupConfig.containerURL` is nil, crash immediately via `fatalError`
- In test environment, a temporary directory is used instead of the App Group, avoiding dependency on it

## Database Integrity Check

`UsageStore.init()` runs `checkIntegrity()` to detect and recover from DB corruption.

### Flow

```
checkIntegrity()
  +-- DB file does not exist → no-op (will be created on first write)
  +-- DB file exists →
      +-- Open DB, run PRAGMA quick_check
      +-- Result == "ok" → no-op (DB is healthy)
      +-- Result != "ok" or open failure →
          +-- Rename DB to .corrupt (remove existing .corrupt first)
          +-- Delete WAL/SHM auxiliary files (-wal, -shm)
          +-- NSLog the corruption event
          +-- Next withDatabase call creates a fresh DB via CREATE TABLE IF NOT EXISTS
```

### Edge cases

| Scenario | Behavior |
|----------|----------|
| `.corrupt` already exists | Removed before rename (`removeItem` + `moveItem`) |
| Rename fails (permissions) | NSLog only; no fallback path created |
| WAL/SHM files present | Deleted alongside the corrupt DB |

## Static convenience methods

The `UsageStore` class provides delegation methods to the `shared` instance.

```swift
static func save(_ result: UsageResult) { shared.save(result) }
static func loadAllHistory() -> [DataPoint] { shared.loadAllHistory() }
static func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] { shared.loadHistory(windowSeconds: windowSeconds) }
```

Callers access these via static methods, e.g., `UsageStore.save(result)`.

## Private helpers

### withDatabase

A generic helper that eliminates DB open/close duplication. Used by all public methods (`save`, `loadAllHistory`, `loadHistory`, `loadDailyUsage`).

```swift
private func withDatabase<T>(_ body: (OpaquePointer) -> T?) -> T?
```

- `sqlite3_open` -> `body(db)` -> `sqlite3_close` (via defer)
- Returns nil on open failure

#### Resolving double-Optional nesting

`withDatabase` returns `T?`. When `body` returns `T?`, the return type of `withDatabase` can become `T??` (Optional of Optional).

For `loadDailyUsage`: `T = Double`, `body: (OpaquePointer) -> Double`, return type is `Double?`. On DB open failure the result is `nil`; otherwise the body's result is wrapped as an Optional.

Each call site resolves the double Optional:

```swift
// loadAllHistory: T = [DataPoint], body returns [] so T? = [DataPoint]?
// ?? [] only triggers when withDatabase returns nil (open failure)
func loadAllHistory() -> [DataPoint] {
    withDatabase { db in
        // ...
        return readDataPoints(stmt)  // returns [DataPoint] (never nil)
    } ?? []
}

// loadHistory: same pattern
func loadHistory(windowSeconds: TimeInterval) -> [DataPoint] {
    withDatabase { db in
        // ...
        return readDataPoints(stmt)
    } ?? []
}

// loadDailyUsage: T = Double, body returns Double -> withDatabase returns Double?
// nil only on DB open failure; otherwise body result is returned as Double?
func loadDailyUsage(since: Date) -> Double? {
    withDatabase { db in
        // ...body returns non-Optional Double
        return totalUsage  // returns Double (not Optional)
    }
    // Return type is Double? (nil if withDatabase returns nil, otherwise body result)
}
```

| Method | body return type | withDatabase return | nil meaning |
|--------|-----------------|-------------------|-------------|
| `loadAllHistory` | `[DataPoint]` | `[DataPoint]?` | DB open failure only |
| `loadHistory` | `[DataPoint]` | `[DataPoint]?` | DB open failure only |
| `loadDailyUsage` | `Double` | `Double?` | DB open failure or insufficient data |
| `save` | `Void` | `Void?` | return value unused |

`save` does not use the return value of `withDatabase`, so double Optional is not a concern.

### readDataPoints

A helper that unifies row reading for `loadAllHistory` and `loadHistory`. Reads 5 columns (timestamp, hourly_percent, weekly_percent, hourly_resets_at, weekly_resets_at) and returns a DataPoint array.

### bindDouble

A private method used for SQLite parameter binding within `save()`.

| Method | Bind type | Behavior on nil |
|--------|-----------|-----------------|
| `bindDouble(_:_:_:)` | `sqlite3_bind_double` | `sqlite3_bind_null` |

A wrapper for safely binding Optional values as NULL/non-NULL.

## loadDailyUsage(since:)

Sums the increase in `weekly_percent` since the specified date and returns the usage increment for the period. Used by the Daily Alert feature.

```swift
func loadDailyUsage(since: Date) -> Double?
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `since` | `Date` | Aggregation start time |

| Return value | Condition |
|-------------|-----------|
| `nil` | Fewer than 2 records in the target period |
| `Double` | Sum of `weekly_percent` increases within the period (>= 0.0) |

### Query

```sql
SELECT u.weekly_percent, ws.resets_at AS weekly_resets_at
FROM usage_log u
LEFT JOIN weekly_sessions ws ON u.weekly_session_id = ws.id
WHERE u.timestamp >= ? AND u.weekly_percent IS NOT NULL
ORDER BY u.timestamp ASC;
```

### Session boundary summation logic

Within the period, `weekly_percent` resets when the session (`weekly_sessions.resets_at`) changes. A simple `latest - earliest` calculation would be inaccurate, so usage is split by session and summed.

```
Session A: [10%, 20%, 30%] -> 30% - 10% = 20%
Session B: [5%, 15%]       -> 15% - 5%  = 10%
Total: 20% + 10% = 30%
```

- Within each session: increase is calculated as `max(0, last - first)` (decreases treated as 0)
- Session boundary: when `weekly_resets_at` changes, the previous session is finalized and a new one begins
- Records with NULL `weekly_resets_at` are grouped together as belonging to the same session
