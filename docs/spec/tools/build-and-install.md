---
Created: 2026-03-04
Updated: 2026-03-15
Checked: 2026-03-15
Checked: -
Deprecated: -
Format: spec-v2.1
Source: tools/build_and_install.py
---

# build_and_install.py Specification

## 0. Meta

| Source | Runtime |
|--------|---------|
| tools/build_and_install.py | Python 3.12+ |
| tools/lib/data_protection.py | Python 3.12+ |
| tools/lib/launchservices.py | Python 3.12+ |
| tools/lib/version.py | Python 3.12+ |

| Field | Value |
|-------|-------|
| Related | tools/tests/ (pytest), tools/rollback.py |
| Test Type | pytest (code/tools/tests/) |

## Overview

A deploy script that performs build, test, and install in a single run. Includes data protection, binary backup, and LaunchServices management.

## Execution Flow

```
1. Data protection: DB backup + rotation
2. File protection: protect_files context manager starts
   |-- stale .backup detection and recovery (layer 2)
   |-- settings.json snapshot
   +-- session-cookies.json snapshot (via shelter_file)
3. Test gate: xcodebuild test
4. File protection: context manager exits (auto-restore via try/finally)
5. LaunchServices: DerivedData deregistration
6. Build: remove stale xctest from DerivedData + xcodebuild build
7. Atomic install:
   |-- Stop app: osascript quit + killall
   |-- cp -R .new: copy new build to .app.new
   |-- Widget verification: run against .new (on failure, .new deleted, current app untouched)
   |-- Binary backup: mv to APPGROUP_DIR/app-backups/.app.v{version}
   |-- mv .new -> .app: atomic swap
   |-- Widget binary size + mtime verification
   +-- SetFile -a B: bundle bit
8. LaunchServices:
   |-- GetFileInfo: bundle bit verification
   |-- DerivedData deregistration
   |-- Entitlements verification (application-groups on app + widget)
   |-- lsregister -f: registration
   |-- pluginkit -e use: widget activation
   |-- killall: widget extension → chronod → NotificationCenter
   +-- sleep(3): wait for chronod restart
9. Deployment verification gate (all must pass or RuntimeError):
   |-- pluginkit -m: widget found in manifest
   |-- pluginkit -m: no DerivedData ghost registration
   +-- lsregister dump: no ghost LS registration
10. Data integrity: row loss detection
11. killall Dock: icon cache refresh
12. Launch: open
```

## Data Protection

### Protected Items

| Protected Item | Mechanism | Timing |
|----------------|-----------|--------|
| usage.db | Backup + rotation | Before tests |
| settings.json | `protect_files` context manager | Before/after tests |
| session-cookies.json | `protect_files` context manager | Before/after tests |
| usage.db integrity | Row loss detection (ATTACH + COUNT) | After install |
| Binary (.app) | Atomic swap (cp .new -> mv) | During install |

### DB Backup + Rotation

- **Target**: `APPGROUP_DIR/usage.db`
- **Backup destination**: `APPGROUP_DIR/backups/usage_YYYYMMDD_HHMMSS.db`
- **Rotation**: Keeps the latest 10; older ones deleted via `Path.unlink()`
- **Pre-test row count**: `SELECT COUNT(*) FROM usage_log`

### File Protection (data_protection.py)

The `protect_files` context manager protects settings.json and session-cookies.json. It has a 3-layer defense mechanism.

#### 3-Layer Defense

| Layer | Mechanism | Protects Against |
|-------|-----------|-----------------|
| 1 | try/finally | Python exceptions (RuntimeError, etc.) |
| 2 | stale .backup detection | SIGKILL, power loss (recovers previous remnants on next run) |
| 3 | cp failure detection | Disk full, permission errors (shutil.copy2 exceptions) |

#### Usage

```python
with protect_files(APPGROUP_SETTINGS):
    with shelter_file(COOKIE_FILE):
        run_test_gate()  # Auto-restore via finally even if exception occurs
```

`shelter_file` is a lightweight context manager for files that may not exist yet. Unlike `protect_files`, it does not require the file to exist at backup time.

#### Internal Behavior

**On entry:**
1. Detect and recover stale `.backup` files for each file (layer 2)
2. Record SHA-256 hash via `hashlib`
3. Copy to `.backup` via `shutil.copy2` (raises on failure: layer 3)

**On exit (finally):**
1. Recalculate SHA-256 for each file
2. If hash differs: restore from `.backup` + WARNING
3. If file was deleted: restore from `.backup` + WARNING
4. If unchanged: delete `.backup`
5. If a restore itself fails, processing continues for remaining files

#### Return Values (_restore_if_changed internal)

- `0`: No change / skipped (file did not exist)
- `1`: Restored (file was corrupted)
- `2`: Restored (file was deleted)

### Data Integrity Check (Row Loss Detection)

- **Target**: `APPGROUP_DIR/usage.db` (post-deploy)
- **Comparison source**: Backup DB created before tests
- **Detection SQL**: `ATTACH backup -> SELECT COUNT(*) FROM backup.usage_log WHERE rowid NOT IN (SELECT rowid FROM main.usage_log)`
- **Results**:
  - `0`: No loss -> proceed normally
  - `> 0`: Row loss detected -> RuntimeError (no automatic recovery; displays backup path for manual intervention)
  - Exception: SQL error -> WARNING

## Atomic Install

### cp .new -> mv Swap

The traditional `rm -rf` + `cp -R` pattern is non-atomic and irrecoverable on interruption. The new approach:

```
1. cp -R build_app .app.new                  # Copy to temporary directory
2. Widget verification (runs against .new)    # On failure: .new deleted, current app untouched
3. shutil.move(.app, APPGROUP_DIR/app-backups/.app.v{version})  # Backup current app
4. .app.new.rename(.app)                     # Swap in new app (mv is atomic)
5. Widget binary size + mtime verification     # Ensure binary is fresh
6. SetFile -a B .app                         # Set bundle bit for Finder
```

- Step 2 failure: only `.new` is deleted; the current app is untouched
- Interruption between steps 3-4: backup exists at `APPGROUP_DIR/app-backups/.app.v{version}`; manual recovery is possible
- Step 5 failure: RuntimeError with installed/source mtime comparison

### Version Retrieval

- Reads `CFBundleShortVersionString` from `Info.plist` using `plistlib`
- Falls back to `"unknown"` on failure
- No PlistBuddy dependency (stdlib only)

## LaunchServices Management

### DerivedData Deregistration

- **Timing**: After tests (before build) + after install
- **Target**: `DerivedData/ClaudeUsageTracker-*/Build/Products/*/ClaudeUsageTracker.app`
- **Additional target**: Apps in `~/.Trash`
- **Method**: `lsregister -u` (deregister)
- **Input validation**: ValueError if `app_name` / `derived_data` is empty

### /Applications Registration

- **Method**: `lsregister -f` (force register)
- **Widget activation**: `pluginkit -e use -i grad13.claudeusagetracker.widget`

### Widget Extension Process Lifecycle

The correct kill order after registration:

1. `killall ClaudeUsageTrackerWidgetExtension` — remove old binary's process
2. `killall chronod` — launchd restarts it immediately; processes `extensionChanged` event
3. `killall NotificationCenter` — discard in-memory rendering buffer

chronod and extension are independent processes. Killing chronod does not kill the extension. The extension must be killed first to prevent chronod from reusing the old binary.

After kill sequence: `sleep(3)` to allow chronod restart.

### Code Signing

Xcode signs all components during `xcodebuild build`. No manual re-signing is needed because:

- Scheme has `buildForTesting="NO"` — xctest is not embedded during build
- Stale xctest (left by `xcodebuild test`) is removed from DerivedData before build
- Xcode detects the missing xctest and re-signs the bundle automatically

Principles (if manual re-signing is ever needed again):
- **Never use `--deep`** — it overwrites entitlements on nested bundles (Apple: `--deep Considered Harmful`)
- **Inner → outer order**: framework → appex → app
- **Always use `--entitlements`** — explicit entitlements file for each component

### Entitlements Verification

Before LaunchServices registration, verify entitlements on both app and widget extension:

- **Command**: `codesign -d --entitlements -`
- **Required**: `com.apple.security.application-groups` on both targets
- **Required**: `com.apple.security.app-sandbox` on widget extension (chronod refuses to load without it)
- **Failure**: RuntimeError

### Widget Registration Verification

- Checks widget extension registration path from `lsregister -dump`
- RuntimeError if registered from DerivedData
- WARNING if not registered from /Applications

### Deployment Verification Gate

After all registration and process restart steps, a verification gate runs as the final check. All conditions must pass or the deploy fails with RuntimeError.

| # | Condition | Command | Expected | Failure |
|---|-----------|---------|----------|---------|
| 1 | Widget in pluginkit manifest | `pluginkit -m -i <WIDGET_ID>` | WIDGET_ID in stdout | `GATE FAIL [1/3]` RuntimeError |
| 2 | No DerivedData ghost in pluginkit | `pluginkit -m -i <WIDGET_ID>` | "DerivedData" not in stdout | `GATE FAIL [2/3]` RuntimeError |
| 3 | No ghost LS registration | `dump_widget_registration()` | "DerivedData" not in output | `GATE FAIL [3/3]` RuntimeError |

The gate function `_verify_widget_deployment()` is a single function that checks all conditions. WARNING-level checks are prohibited — all failures are RuntimeError.

## App Group Path

```
$HOME/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker/
|-- usage.db
|-- settings.json
|-- session-cookies.json
|-- backups/
|   +-- usage_YYYYMMDD_HHMMSS.db  (max 10)
+-- app-backups/
    +-- ClaudeUsageTracker.app.v{version}
```

## Error Behavior

| Situation | Behavior |
|-----------|----------|
| Test failure | RuntimeError (build and install are not performed) |
| Build artifact not found | RuntimeError |
| Widget appex not found in .new | RuntimeError (.new deleted, current app untouched) |
| Widget binary stale (mtime) or size mismatch | RuntimeError |
| Bundle bit not set | RuntimeError |
| Entitlements missing (application-groups) | RuntimeError |
| Widget registered from DerivedData (LS) | RuntimeError |
| GATE FAIL [1/3]: Widget not in pluginkit | RuntimeError |
| GATE FAIL [2/3]: Ghost in pluginkit | RuntimeError |
| GATE FAIL [3/3]: Ghost LS registration | RuntimeError |
| DB row loss detected | RuntimeError (displays backup path; no automatic recovery) |
| pluginkit -e use failure | WARNING (continues) |
| Widget not in pluginkit -m (pre-gate) | WARNING (continues; gate will catch) |
| Widget not registered from /Applications | WARNING (continues) |
| settings.json modification detected | WARNING + restore (automatic, continues) |
| session-cookies.json modification detected | WARNING + restore (automatic, continues) |

## Internal Functions

| Function | Responsibility |
|----------|----------------|
| `find_derived_data_dir()` | Find correct DerivedData via WorkspacePath matching; fallback to newest by mtime |
| `run_test_gate()` | xcodebuild test |
| `build_app()` | Remove stale xctest from DerivedData + xcodebuild build + artifact verification; returns Path |
| `install_app(build_app_path)` | Stop app + atomic install + widget verification + size/mtime check + bundle bit |
| `verify_bundle_bits(app_path)` | Verify bundle bit via GetFileInfo |
| `register_and_clean(app_path)` | Deregister stale copies + entitlements verify + LS registration + process kill |
| `verify_deployment(app_path)` | Deployment verification gate: 3 conditions, all must pass or RuntimeError |
| `check_data_integrity(backup_file)` | Row loss detection (ATTACH + COUNT) |
| `refresh_and_launch(app_path)` | killall Dock (icon cache refresh) + open app |

## Related Scripts

| Script | Responsibility |
|--------|----------------|
| `tools/lib/runner.py` | `run()` — subprocess wrapper with consistent error handling (check/allow_fail/label) |
| `tools/lib/db_backup.py` | `backup_database()` + `rotate_backups()` + `check_lost_rows()` — DB backup and integrity |
| `tools/lib/data_protection.py` | `protect_files` context manager (3-layer defense) + `shelter_file` (backup loss detection) |
| `tools/lib/launchservices.py` | `LSREGISTER` path constant + `deregister_stale_apps()` + `register_app()` + `dump_widget_registration()` (entry boundary search) |
| `tools/lib/version.py` | `get_app_version()` — version string retrieval via plistlib (specific exception handling) |
| `tools/rollback.py` | Binary rollback (atomic swap). Env vars restricted to TEST_MODE. Does not cover data (DB, cookies) |
| `tools/tests/` (pytest) | Tests for runner + data protection + deploy gate + rollback + lib functions + find_derived_data |
