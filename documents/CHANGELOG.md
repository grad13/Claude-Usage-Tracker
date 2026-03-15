<!-- meta: created=2026-02-21 updated=2026-03-14 checked=never -->
# Changelog

## [Unreleased]

### Improved
- **Widget footer**: Compact layout (reduced height, font size unified with chart labels)
- **Widget footer**: Removed system content margins (`contentMarginsDisabled`) to maximize chart area
- **Widget refresh**: Entire footer row acts as refresh button (larger tap target)
- **Widget refresh**: Show "updating..." feedback for 1.5 seconds after tap
- **Widget refresh**: Blue refresh icon to indicate tappability
- **Widget countdown**: Short minute-based format for Next display ("23 sec" → "2m")

## [1.0.3] - 2026-03-14

### Fixed
- **Widget snapshot**: UserDefaults → ファイル I/O に変更。sandbox の有無で読み書き先がズレてウィジェットにデータが表示されない問題を修正
- **セッション維持**: テスト用 ViewModel が本番の WKWebsiteDataStore を破壊し、デプロイ後にセッション Cookie が消える問題を修正（nonPersistent で隔離）

## [1.0.2] - 2026-03-14

### Fixed
- Widget stale data: switched widget data sharing from SQLite direct read to UserDefaults (App Group) snapshot for reliable updates

### Changed
- Widget timeline policy changed from `.after(5min)` to `.never` — updates driven by `reloadTimelines()` only
- Removed WidgetKit reload throttling (no longer needed with UserDefaults-based reads)
- Added future timeline entry at reset time for automatic widget refresh at usage window reset

## [1.0.1] - 2026-03-13

### Fixed
- Widget not updating: throttle WidgetKit reloadAllTimelines() to 5-minute intervals to stay within daily reload budget

### Changed
- Refresh Dock icon cache after install to prevent folder-icon display bug

## [1.0.0] - 2026-03-13

First public release with Developer ID signing and Apple notarization.

### Added
- Developer ID signed and Apple notarized binary
- GitHub Actions CI (xcodebuild test + pytest on push/PR)

### Changed
- Consolidated Alert Settings menu: unified submenu with None + threshold options
- Git author unified to grad13

## [0.10.1] - 2026-03-07

### Changed
- Consolidate Alert Settings menu: Weekly/Hourly/Daily alerts now use unified submenu with None + threshold options instead of separate toggle and threshold items

## [0.10.0] - 2026-03-07

### Added
- Color Theme setting (System/Light/Dark) for menu bar graphs
- Sync Graph Settings (colors, theme) to Widget and Analysis page
- Widget reads color presets from shared settings.json via WidgetColorThemeResolver
- Analysis page applies dynamic chart colors and light/dark theme from settings
- ChartColorPreset.hexString property for CSS color output
- AnalysisSchemeHandler settingsProvider DI for testability

### Changed
- Widget color/theme changes trigger immediate widget reload via WidgetCenter

## [0.9.12] - 2026-03-07

### Added
- Light mode support for menu bar graphs (auto-follows system appearance)
- Privacy manifest (PrivacyInfo.xcprivacy) for main app and widget
- Network error auto-retry with exponential backoff (30s/60s/120s, max 3)
- Database integrity check on init (PRAGMA quick_check, auto-recovery)
- Settings file corruption recovery (.bak rename + defaults reset)
- GitHub issue templates (bug report, feature request)
- GitHub Actions CI workflow (xcodebuild test + pytest on PRs)

### Changed
- Unified print() to NSLog() in Settings.swift

### Fixed
- Menu bar text/graph invisible in light mode (.white hardcoded)
- Deploy script session-cookies.json protection (shelter_file fix)

## [0.9.11] - 2026-03-06

### Fixed
- App shown as folder in Dock after install (bundle bit not set)
- Auth errors now show "Session expired" instead of raw diagnostic string
- Auth errors transition to Sign In state instead of showing red error text

### Added
- Bundle bit verification in deploy script (raises on missing B flag)
- Tests for bundle bit detection (missing → error, present → pass)

## [0.9.10] - 2026-03-06

### Changed
- Extracted GraphCalc to Shared framework (tests-to-code C1 fix)
- Removed test logic reimplementations — tests now call production code directly
- Split S6 test files by responsibility (40 test files analyzed)
- Cleaned up transient skill analysis artifacts

## [0.9.9] - 2026-03-06

### Fixed
- Analysis window now reloads on reopen (new sessions appear after weekly turnover)

### Added
- 30 tests from spec: protocols conformance, analysis JS logic, mini-usage-graph logic
- MiniUsageGraph: extracted usageValue/fillEndFrac as internal for testability

### Changed
- protocols.md: removed DI-03 (SnapshotWriting) and DI-07 (TokenSyncing) to match code
- Refactored UsageModels.swift and UsageViewModel+Debug.swift extraction

## [0.9.8] - 2026-03-06

### Added
- 4-mode session navigation: Session Weekly/Hourly, Calendrical Week/Day
- Hourly session bands as chart background (alternating stripes per hourly session)
- Future zone stripes for Session Hourly mode
- Time ticks and hour grid lines for short time scales

### Changed
- Unified X-axis label rendering via plugin across all modes
- Chart fills viewport height dynamically (no fixed height)
- Removed chart panel border/background for cleaner look
- Disabled Chart.js animation for instant rendering
- Show start/end times in Hourly Session dropdown labels

### Removed
- "Usage Timeline" heading
- Day-of-week from Calendrical Day labels

## [0.9.7] - 2026-03-06

### Removed
- Token/predict/cost features removed from analysis page and backend (TokenStore, JSONLParser, CostEstimator, UsageViewModel+Predict)
- Analysis page simplified from 6-tab system to usage-only chart with session navigation

## [0.9.6] - 2026-03-06

### Fixed
- **Sign-in detection**: Session not detected after OAuth popup completion or re-sign-in after sign-out
  - Call `handleSessionDetected()` after popup close in `checkPopupLogin()`
  - Call `handlePopupClosed()` on sheet dismiss
  - Restart `startLoginPolling()` after `signOut()`

## [0.9.5] - 2026-03-04

### Fixed
- **Flaky test fix**: Pin `now` in all `DisplayHelpersRemainingTextTests` to eliminate timing-dependent instability
- **Widget % text position**: Switch from Y-coordinate-based to percent-based positioning (below at >80%, above otherwise)
- **Deploy script**: Replace `shutil.copytree` with `ditto` to preserve macOS bundle bit
- **Stale widget build**: Identify stale widget extension left in `/private/tmp/cut-build/`

### Changed
- **Widget icon**: Add AppIcon to widget extension (`ASSETCATALOG_COMPILER_APPICON_NAME`)
- **Remove Analysis summary cards**: Remove statistics cards (Usage Records, Sessions, etc.) from top of analysis page

## [0.9.3] - 2026-03-04

### Changed
- **Rewrite deploy scripts in Python**: Replace all bash scripts (build-and-install.sh, rollback.sh, lib/) with Python
  - `protect_files` context manager with try/finally for automatic restore (eliminates sign-out bug)
  - Atomic install (cp .new → mv swap) prevents app loss on interruption
  - 3-layer defense: try/finally + stale .backup detection + cp failure detection
  - Use plistlib / hashlib / shutil to eliminate external tool dependencies
  - 27 tests (8 new: exception auto-recovery, sign-out bug E2E reproduction, etc.)

## [0.9.2] - 2026-03-04

### Added
- **Analysis: Weekly Session navigation**: Replace date range controls with Weekly Session / Daily mode toggle + prev/next navigation. Default shows latest weekly session
- **Analysis: Weekly session boundary visualization**: Split weekly line rendering by session with pink dashed markers at boundaries
- **Analysis: Daily mode**: Navigate by day with keyboard arrow key support
- **meta.json weeklySessions list**: Provide all weekly session resets_at timestamps for session navigation
- **5h Sessions count**: Show 5h session count in stats bar for the selected period

### Changed
- **Code refactoring**: Fix mixed responsibilities, data inconsistencies, and schema mismatches in 3 files flagged by should-analysis
  - Extract `WidgetMiniGraph` from `WidgetMediumView.swift` to its own file. Split Canvas body into 10 private methods
  - `UsageStore`: Add `withDatabase` helper to eliminate DB open/close duplication. Unify row reading with `readDataPoints`. Add JOIN to `loadHistory` (returns `resetsAt`). Replace `print` with `NSLog`
  - `TokenStore`: Add `speed` / `web_search_requests` columns (idempotent ALTER TABLE migration). Expand upsert/query to 9 columns (eliminate hardcoding). `AnalysisSchemeHandler`: Add `speed` / `web_search_requests` to tokens.json

## [0.9.0] - 2026-03-03

### Added
- **Orbital app icon**: macOS icon set (16–1024px) generated from SVG design
- `rollback-rename.sh`: Rollback script for rename deployment

### Fixed
- **Widget App Group support**: Set `DEVELOPMENT_TEAM` in pbxproj, add `-allowProvisioningUpdates` to xcodebuild. Widget can now read data from new App Group
- **usage.db migration**: Change from INSERT OR IGNORE merge to force-copy (`cp -f`). Guarantee exact match with old App Group
- **build-and-install.sh**: Remove automatic merge from backup (conflicts with force-copy)

### Changed
- Retire WeatherCC.app and fully migrate to ClaudeUsageTracker

## [0.8.2] - 2026-03-02

### Changed
- **Deploy script rename: WeatherCC → ClaudeUsageTracker**
  - `migrate-to-appgroup.sh`: Change target to new App Group (`group.grad13.claudeusagetracker`). Add old App Group (`C3WA2TT222.grad13.weathercc`) as legacy source. Add `tokens.db` / `snapshot.db` migration sections
  - `build-and-install.sh`: Update `APPGROUP_DIR` to new path. Add LaunchServices cleanup for old `WeatherCC-*` DerivedData / Trash
  - `test-migration.sh`: Update helper paths to new App Group. Add 7 helper functions for old App Group testing. Add 4 tests (tokens.db / snapshot.db migration, old App Group usage.db merge, old App Group settings.json migration) → all 20 tests pass
  - `_documents/CLAUDE.md`: Update project name, Bundle ID, Source Files, App Group ID

## [0.8.1] - 2026-03-02

### Changed
- **Git-track deploy scripts + compilation support**
  - Move `code/_tools/` → `tools/` (now git-tracked)
  - `build-and-install.sh`: Update APP_NAME / SCHEME / xcodeproj / xctest / appex / pluginkit ID to renamed ClaudeUsageTracker. Add `DEVELOPMENT_TEAM`
  - Update usage comments in scripts to current paths
  - Remove stale `code/WeatherCC.xcodeproj` (empty shell)

## [0.8.0] - 2026-02-28

### Added
- **Alert notifications**: 3 types of usage alerts — Weekly / Hourly / Daily
  - Weekly Alert: macOS notification when 7-day remaining % falls below threshold
  - Hourly Alert: macOS notification when 5-hour remaining % falls below threshold
  - Daily Alert: Notification when usage in period exceeds threshold (switchable between date-based / session-based)
  - `AlertChecker`: Threshold evaluation + per-session duplicate notification prevention (in-memory)
  - `NotificationManager`: UNUserNotificationCenter wrapper
  - Alert Settings submenu (ON/OFF toggles + threshold presets + Daily definition toggle)
  - `UsageStore.loadDailyUsage(since:)`: Aggregate usage across session boundaries
  - DI protocols: `AlertChecking` (DI-08), `NotificationSending` (DI-09)
  - Tests: AlertCheckerTests (29), NotificationManagerTests (4), ViewModel integration tests (2)

### Fixed
- Deploy pipeline stabilization
  - Fix 6 tests in AnalysisBugHuntingTests: Change `hourly_resets_at: null` to valid values, update expectations to v0.7.2 spec (fill: true, borderWidth: 0.75, dataCount: 3)
  - build-and-install.sh: Remove "expected failure tolerance logic", restore simple exit code check
  - LaunchServices deregister: Change `Build/Products/Debug/` → `Build/Products/*/` (cover Release builds too)

## [0.7.4] - 2026-02-27

### Fixed
- Fix X-axis range drift when switching Analysis tabs
  - Add `min`/`max` to `timeXScale()` so Usage/Cost/Cumulative charts share the same range
  - Save user-specified date range to global variables in `loadData()`
  - "All" preset delegates to Chart.js auto-calculation (min/max = null)

## [0.7.3] - 2026-02-27

### Fixed
- Fix Analysis window not opening on widget click
  - `AppDelegate.handleURL` was intercepting URL events via `NSAppleEventManager`, preventing delivery to SwiftUI's `.handlesExternalEvents(matching:)`
  - Remove `NSAppleEventManager.setEventHandler` registration and `handleURL` method, delegate routing to SwiftUI

## [0.7.2] - 2026-02-27

### Changed
- **Major Usage Timeline chart improvements**
  - Session background bands: Pattern C (even = diagonal stripes / odd = semi-transparent solid fill)
  - Hourly: Area fill (alpha 0.6), line width 0.75, marker 1px
  - Weekly: Render in foreground (`order: -1`)
  - Draw date boundary lines behind datasets
- `buildHourlySessions()`: Skip NULL session_id records (idle periods)
- Add y=0 point at resets_at to bring usage back to 0 at session end

### Added
- **Custom crosshair tooltip**: Mouse-following vertical line + simultaneous Hourly/Weekly value display
- **Legend grouped toggle**: Click Hourly to bulk show/hide all sessions

### Removed
- **Migration cleanup**: Remove all rollback code and legacy schema support from v0.7.0 schema normalization
  - `UsageStore.swift`: Remove `migrateSchemaIfNeeded()` + `insertSession()` + init call (~180 lines removed, 425→246 lines)
  - `migrate-to-appgroup.sh`: Remove `OLD_APPGROUP` variable, old App Group path references, old schema detection + conversion SQL
  - `test-migration.sh`: Remove old App Group tests (Test 9-13), helper functions. Renumber Test 14 → Test 9
  - `UsageStoreTests.swift`: Remove `testMigration_oldSchemaToNew()` + `testMigration_newSchemaNotMigrated()`

### Spec / Docs
- Update `usage-store.md` to current schema (3-table structure)
- Expand deploy tool tests (`test-migration.sh`, `test-build-install.sh`)
- Update 3 deploy scripts for v0.7.0 new schema
- Spec refactoring (split architecture.md, split settings.md, convert to spec-v2.1 format)

## [0.7.1] - 2026-02-27

### Added
- Display version number in menu (before Quit button, `v0.7.1` format)

## [0.7.0] - 2026-02-27

### Changed
- **usage_log schema normalization**: Extract denormalized `resets_at` columns into `hourly_sessions` / `weekly_sessions` tables (FK references)
- **Timestamps**: ISO8601 TEXT → epoch INTEGER (second precision)
- **Column names**: `five_hour_` → `hourly_`, `seven_day_` → `weekly_` (DB layer only, Swift naming preserved)
- **Remove unused columns**: status × 2, limit × 2, remaining × 2, raw_json
- **Auto migration**: Detect legacy schema on first launch and convert to new DB (auto-create `usage.db.bak` backup)
- **AnalysisSchemeHandler**: Switch to LEFT JOIN queries, update JSON response key names
- **analysis.html**: Remove 5-minute tolerance workaround in `buildHourlySessions()` (simplify to direct epoch comparison after normalization), support epoch timestamps
- **Test infrastructure**: Add try/catch wrapper to `evalJS()` (immediate error reporting instead of hanging on undefined function calls)

## [0.6.7] - 2026-02-26

### Added
- **Analysis date range selection**: Add global date range UI to top of Analysis view
  - From/To date inputs + preset buttons (7d / 30d / All) + Apply button
  - Initial load shows weekly session range only (`meta.json`'s `latestSevenDayResetsAt` - 7 days)
  - Add `from` / `to` query parameter support to `wcc://usage.json` / `wcc://tokens.json` (SQL WHERE clause)
  - Add `wcc://meta.json` endpoint (oldest/latest timestamp + latestSevenDayResetsAt)
  - Unify all 4 tabs (Usage / Cost / Efficiency / Cumulative) under global filter
  - Remove Efficiency tab's standalone date filter (eliminate duplication)

## [0.6.6] - 2026-02-26

### Changed
- **Code refactoring**: Split 3 must-flagged files (500+ lines) into 13 files. No behavior changes, pure structural change
  - `WeatherCCApp.swift` (522→47 lines): Extract MenuContent, LoginWindowView, AnalysisWindowView, MenuBarLabel, MiniUsageGraph to individual files
  - `AnalysisExporter.swift` (709→18 lines): Extract HTML/CSS/JS to bundle resource `Resources/analysis.html`. Load via Bundle(for:)
  - `UsageViewModel.swift` (678→320 lines): Extract Session/Settings/Predict to extension files. Move WebViewCoordinator + CookieChangeObserver to individual files
- 596 tests all pass (no test changes)

## [0.6.5] - 2026-02-26

### Fixed
- **Remove sql.js remnants**: Change Analysis page "Loading sql.js..." to "Loading data...". Remove old implementation references (sql.js/WASM/wcc://*.db) from HTML template, WeatherCCApp.swift comments, and docstrings
- **Fix 23 test failures**: Rewrite AnalysisSchemeHandler tests from .db binary delivery assumption to Swift-side SQLite query → JSON response assumption. Change setUp from dummy text to real SQLite DB. Remove 13 obsolete tests, clean up docstrings

## [0.6.4] - 2026-02-26

### Fixed
- **Enable Analysis data loading**: `claudeProjectsDirectories()` was returning `[]`, disabling JSONL sync. Changed to return `~/.claude/projects/`, enabling data display in Cost / Efficiency / Cumulative tabs. No TCC constraints in Sandbox-off environment (comment was a remnant from Sandbox-on era)

## [0.6.3] - 2026-02-25

### Fixed
- **Graph: Extend area fill**: Fix issue where post-last-data-point area was filled with no-data grey. Since usage is monotonically non-decreasing until reset, horizontally extend the last fetched value to `min(now, resetsAt)` with area fill. Limit no-data grey to post-reset → now only
- **Widget: Fix marker position**: Move marker from last data point to area extension endpoint (= now or resetsAt). Matches spec definition of "x-coordinate at current time"

## [0.6.1] - 2026-02-24

### Fixed
- **Widget display pipeline fix**: `xcodebuild test` registers DerivedData's Widget Extension with LaunchServices, and chronod caches that path, causing widget to not display. Modified `build-and-install.sh` to deregister all ghost registrations from DerivedData/Trash after test and before install, registering only `/Applications`
- **Widget registration verification step**: After install, verify via `lsregister -dump` that Widget Extension is registered from `/Applications`. Abort with error if DerivedData path remains

### Added
- **Widget pipeline integration tests (6)**: Verify SnapshotStore save → load returns data shape required for widget rendering (includes rendering contract tests)
- **Investigation report**: `docs/report/widget-display-pipeline.md` — root cause analysis, fixes, macOS WidgetKit command reference, troubleshooting procedures

## [0.6.0] - 2026-02-24

### Changed
- **Move Analysis page to in-app window**: Change from external browser + JSON embedding → WKWebView + sql.js. Click "Analysis" in menu to display in-app window (iStats Menus-style UX)
  - New `AnalysisSchemeHandler`: Custom URL scheme `wcc://` serves SQLite DB files to WKWebView. Bypasses file:// CORS restrictions
  - Simplify `AnalysisExporter`: Remove `usageDataJSON()` / `tokenDataJSON()` / `exportAndOpen()`. Keep HTML template only
  - HTML template: Query SQLite directly with sql.js (eliminates Swift-side JSON conversion)
  - Port cost calculation to JS (reimplement CostEstimator price table in JavaScript)
- **Rewrite tests**: Replace `AnalysisExporterTests` JSON serialization tests → `AnalysisSchemeHandler` MIME type, delivery, and 404 tests

## [0.5.1] - 2026-02-23

### Changed
- **Graph: Remove back-fill + add no-data grey**: Remove back-fill that extended nearest value into data-absent periods. Instead, fill no-data intervals (window start → first fetch, last fetch → now) with light grey (`white.opacity(0.06)`) for visual distinction
- **Percent text positioning**: Default to above marker (opposite side of area fill). Show below only within 14px of top edge. Eliminates overlap with area fill

## [0.5.0] - 2026-02-23

### Fixed
- **API format support**: Support Format A (`five_hour`/`seven_day` + `utilization`). Auto-detect between Format A and Format B (`windows`/`5h`/`7d`)
- **SnapshotStore: Keychain → file**: Switch from Keychain to App Group file (`snapshot.json`) due to unstable Keychain in macOS Widget Extension sandbox
- **Widget rendering fix**: Change `.containerBackground(.fill.tertiary)` → `.clear` (`.fill.tertiary` was covering Canvas rendering)
- **NULL data prevention**: Add code guard to `UsageStore.save()` + CHECK constraint in CREATE TABLE. Add migration to auto-delete existing NULL rows on launch

### Added
- 36 new tests (310 total): Fetcher 15, ViewModel 8, UsageStore 3, SnapshotStore 10

## [0.3.1] - 2026-02-22

### Changed
- **Remove org ID fallback chain**: Eliminate JS 4-stage fallback (cookie → performance API → HTML regex → `/api/organizations`). Read `lastActiveOrg` cookie directly from `WKHTTPCookieStore` in Swift, pass to JS via `callAsyncJavaScript(arguments:)`. JS reduced from ~60 lines to 12
- **Small widget**: Change from text display (percent + remaining time) → WidgetMiniGraph (5h / 7d stacked vertically)

### Added
- `CLAUDE.md` (root): Project development rules and process
- `README.md` (root): Project overview + AgentLimits credit

### Removed
- Remove `/api/organizations` call (Approach A) entirely
- Remove 4 JS org ID functions (`readCookieValue`, `findOrgIdFromResources`, `findOrgIdFromHtml`, `findOrgIdFromApi`)

## [0.3.0] - 2026-02-22

### Added (Phase 3: Widget)
- **macOS WidgetKit widget**: Small / Medium / Large sizes
  - Small: 5h / 7d percentage + remaining time
  - Medium: 5h / 7d graphs side by side + percent + remaining time (1 line)
  - Large: Section graphs (large) + percent + remaining time + Est. cost
- **WeatherCCShared framework**: Shared code between main app and widget
  - `UsageSnapshot` / `HistoryPoint` data models
  - `SnapshotStore` — Share snapshots via App Group file
  - `AppGroupConfig` — App Group ID constants
- **App Group file sharing**: Share data between app ↔ widget via `snapshot.json` in App Group container
- **App Sandbox enabled**: Sandbox main app (prerequisite for Keychain sharing)
  - `com.apple.security.network.client` — HTTP communication
  - `com.apple.security.temporary-exception.files.absolute-path.read-only` — JSONL reading
- **build-and-install.sh**: Automation script for build → `/Applications` copy → LaunchServices registration → chronod restart → launch

### Changed
- **Graph rendering improvements**: Skip data points before window start (fix old pre-reset data appearing at left edge)
- **Graph current time extension**: Horizontally extend area from last data point to current time (widget graph)
- **isLoggedIn support**: Change graph background to red (#3A1010) when logged out (match menu bar)

### Fixed
- Fix WidgetMediumView notFetchedView from debug display to clean fallback

## [Unreleased]

### Added (Phase 1 UI Polish)
- **Menu bar mini graph**: Replace numeric text with Canvas-based graph (5h / 7d side by side, color-coded: green < 70%, orange 70-90%, red >= 90%)
- **Remaining time display**: Show "resets in Xh Ym" / "Xd Yh" format in dropdown
- **Visit Usage Page button**: Open claude.ai/settings/usage in default browser

### Changed (Phase 1 UI Polish)
- **UsageFetcher parse overhaul**: Change from `json["five_hour"]["utilization"]` → `json["windows"]["5h"]` with `limit`/`remaining` calculation. Change `resets_at` from ISO 8601 → Unix seconds
- **UsageResult status fields**: Add `fiveHourStatus` / `sevenDayStatus` (within_limit / approaching_limit / exceeded_limit)
- **UsageViewModel time calculations**: Add `timeProgress()` / `remainingTimeText()` / corresponding computed properties
- Remove unused ISO 8601 parsers (`parseDate`, `formatterWithFractional`, `formatterNoFractional`, `trimFractionalSeconds`)

### Added
- **Phase 2: JSONL estimation (Predict)** — Estimate token costs from local JSONL logs
  - `JSONLParser.swift` — JSONL file reading, parsing, requestId deduplication
  - `CostEstimator.swift` — Per-model cost calculation (Opus/Sonnet/Haiku), window aggregation
  - `JSONLParserTests.swift` — 8 tests (parsing, filtering, deduplication, error handling)
  - `CostEstimatorTests.swift` — 11 tests (cost calculation, window filter, token breakdown)
  - `docs/spec/phase2-spec.md` — Phase 2 specification

### Changed (Phase 1 Improvements — based on agentlimits-approach-extract.md)
- **Improvement 1**: Change OAuth popup from `addSubview` → SwiftUI `.sheet()` modal
- **Improvement 2**: Consolidate org ID retrieval + API call into single JS script (remove Swift-side branching)
- **Improvement 3**: Change fetch control from `pendingFetch` (one-shot) → `isAutoRefreshEnabled` (disable only on auth error)
- **Improvement 4**: Change sign-out to full deletion + individual cookie deletion (double-delete approach)
- **Improvement 5**: Extend date parsing from 2-stage → 3-stage (truncate sub-millisecond fractional seconds)
- **Improvement 6**: Log raw API response JSON in debug builds
- Add 10 `FetcherTests` (3-stage date parsing + isAuthError)

### Changed (from v0.1.0)
- Org ID retrieval: `/api/organizations` API → Cookie (`lastActiveOrg`) + JS fallback
- Delegate placement: Inside LoginWebView → UsageViewModel's WebViewCoordinator
- Login detection: Fetch success check → `sessionKey` Cookie observation (`WKHTTPCookieStoreObserver`)
- Navigation restriction: Usage page only → entire claude.ai domain
- Page ready detection: KVO `isLoading` → `didFinish` delegate
- Redirect control: Max 2 count → 5-second cooldown
- Cookie store: `WKWebsiteDataStore(forIdentifier:)` → `.default()` (reverted)
- LoginWebView: Remove OAuth, navigation, and redirect logic; simplify to thin wrapper

## [0.1.0] - 2026-02-21

### WeatherCC MVP
- Menu bar resident app (`5h: XX% / 7d: YY%` display)
- WKWebView for claude.ai login (Google OAuth support)
- JavaScript execution for usage API fetch
- Background auto-fetch on launch
- Auto-fetch on page load completion after login
- 5-minute interval auto-refresh
- Sign In / Sign Out toggle
- Post-login navigation restriction (usage page only)
- Start at Login (SMAppService)
- Rename ClaudeLimits → WeatherCC
