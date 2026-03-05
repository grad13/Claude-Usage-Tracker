---
Created: 2026-03-04
Updated: 2026-03-06
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
   +-- session-cookies.json snapshot
3. Test gate: xcodebuild test
4. File protection: context manager exits (auto-restore via try/finally)
5. LaunchServices: DerivedData deregistration
6. Build: xcodebuild build
7. Atomic install:
   |-- Stop app: osascript quit + killall
   |-- cp .new: copy new build to .app.new
   |-- Widget verification: run against .new (on failure, .new deleted, current app untouched)
   |-- Binary backup: mv to .app.v{version}
   +-- mv .new -> .app: atomic swap
8. LaunchServices: registration + chronod restart
9. Widget registration verification
10. Data integrity: row loss detection
11. Launch: open
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
with protect_files(APPGROUP_SETTINGS, COOKIE_FILE):
    run_test_gate()  # Auto-restore via finally even if exception occurs
```

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
1. shutil.copytree(build_app, .app.new)     # Copy to temporary directory
2. Widget verification (runs against .new)   # On failure: .new deleted, current app untouched
3. .app.rename(.app.v{version})              # Backup current app (mv is atomic)
4. .app.new.rename(.app)                     # Swap in new app (mv is atomic)
```

- Step 2 failure: only `.new` is deleted; the current app is untouched
- Interruption between steps 3-4: backup exists at `.app.v{version}`; manual recovery is possible

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
- **chronod restart**: `killall chronod` (waits 3 seconds)

### Widget Registration Verification

- Checks widget extension registration path from `lsregister -dump`
- RuntimeError if registered from DerivedData
- WARNING if not registered from /Applications

## App Group Path

```
$HOME/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker/
|-- usage.db
|-- settings.json
|-- session-cookies.json
+-- backups/
    +-- usage_YYYYMMDD_HHMMSS.db  (max 10)
```

## Error Behavior

| Situation | Behavior |
|-----------|----------|
| Test failure | RuntimeError (build and install are not performed) |
| Build artifact not found | RuntimeError |
| Widget appex not found | RuntimeError (.new deleted, current app untouched) |
| Widget registered from DerivedData | RuntimeError |
| DB row loss detected | RuntimeError (displays backup path; no automatic recovery) |
| settings.json modification detected | WARNING + restore (automatic, continues) |
| session-cookies.json modification detected | WARNING + restore (automatic, continues) |

## Internal Functions

| Function | Responsibility |
|----------|----------------|
| `backup_database()` | DB backup + rotation (keeps 10) |
| `run_test_gate()` | xcodebuild test |
| `build_app()` | xcodebuild build + artifact verification; returns Path |
| `install_app(build_app_path)` | Stop app + atomic install + widget verification |
| `register_and_verify(backup_file)` | LaunchServices registration + widget verification + data integrity + launch |

## Related Scripts

| Script | Responsibility |
|--------|----------------|
| `tools/lib/data_protection.py` | `protect_files` context manager (3-layer defense) |
| `tools/lib/launchservices.py` | `LSREGISTER` path constant + `deregister_stale_apps()` + `register_app()` |
| `tools/lib/version.py` | `get_app_version()` -- version string retrieval via plistlib |
| `tools/rollback.py` | Binary rollback (atomic swap). Does not cover data (DB, cookies) |
| `tools/tests/` (pytest) | Tests for data protection + rollback + lib functions (27 cases) |
