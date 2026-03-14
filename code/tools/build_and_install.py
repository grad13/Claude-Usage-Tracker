#!/usr/bin/env python3
"""Build, test, and install ClaudeUsageTracker.

Replaces build-and-install.sh with proper error handling:
- try/finally for file protection (no more forgotten restore)
- Atomic install (cp .new → mv swap, never leaves broken app)
- Structured error handling instead of || true
"""

from __future__ import annotations

import os
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# Add lib/ to path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from data_protection import protect_files, shelter_file
from launchservices import (
    LSREGISTER,
    deregister_stale_apps,
    dump_widget_registration,
    register_app,
)
from version import get_app_version

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent.parent.parent
APP_NAME = "ClaudeUsageTracker"
SCHEME = "ClaudeUsageTracker"
DERIVED_DATA = Path.home() / "Library/Developer/Xcode/DerivedData"
INSTALL_DIR = Path("/Applications")
APPGROUP_DIR = (
    Path.home()
    / "Library/Group Containers/group.grad13.claudeusagetracker"
    / "Library/Application Support/ClaudeUsageTracker"
)
APPGROUP_DB = APPGROUP_DIR / "usage.db"
APPGROUP_SETTINGS = APPGROUP_DIR / "settings.json"
COOKIE_FILE = APPGROUP_DIR / "session-cookies.json"
WIDGET_ID = "grad13.claudeusagetracker.widget"


# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------


def find_derived_data_dir() -> Path | None:
    """Find the DerivedData directory for this project."""
    if not DERIVED_DATA.exists():
        return None
    for d in DERIVED_DATA.iterdir():
        if d.is_dir() and d.name.startswith(f"{APP_NAME}-"):
            return d
    return None


def rotate_backups(backup_dir: Path, keep: int = 10) -> None:
    """Rotate backup files, keeping the newest `keep` files."""
    backups = sorted(backup_dir.glob("usage_*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in backups[keep:]:
        old.unlink()


def backup_database() -> tuple[int, Path | None]:
    """Backup usage.db and rotate old backups (keep newest 10).

    Returns (pre_count, backup_path).
    """
    if not APPGROUP_DB.exists():
        return 0, None

    # Count rows before backup
    try:
        conn = sqlite3.connect(str(APPGROUP_DB))
        conn.execute("PRAGMA query_only = ON")
        pre_count = conn.execute("SELECT COUNT(*) FROM usage_log").fetchone()[0]
        conn.close()
    except sqlite3.Error:
        pre_count = 0

    # Create backup
    backup_dir = APPGROUP_DIR / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_file = backup_dir / f"usage_{datetime.now():%Y%m%d_%H%M%S}.db"
    shutil.copy2(str(APPGROUP_DB), str(backup_file))
    print(f"==> DB backup: {pre_count} rows → {backup_file}")

    rotate_backups(backup_dir)

    return pre_count, backup_file


def run_test_gate() -> None:
    """Run xcodebuild test. Raises on failure."""
    print("==> Running unit tests...")
    result = subprocess.run(
        [
            "xcodebuild",
            "-project", str(PROJECT_DIR / "code/ClaudeUsageTracker.xcodeproj"),
            "-scheme", SCHEME,
            "-destination", "platform=macOS",
            "DEVELOPMENT_TEAM=C3WA2TT222",
            "-allowProvisioningUpdates",
            "test",
        ],
        capture_output=True,
        text=True,
    )
    # Show last 5 lines of output
    lines = result.stdout.splitlines()
    for line in lines[-5:]:
        print(line)

    if result.returncode != 0:
        raise RuntimeError("Unit tests failed. Aborting deployment.")


def build_app() -> Path:
    """Build the app and return the path to the built .app.

    Removes stale xctest from DerivedData before building so that
    xcodebuild re-signs the bundle without the test target.
    (Scheme has buildForTesting=NO, but xcodebuild test leaves
    xctest in DerivedData which persists across incremental builds.)
    """
    # Remove stale xctest from DerivedData (left by xcodebuild test)
    dd_dir = find_derived_data_dir()
    if dd_dir:
        stale_xctest = (
            dd_dir / "Build/Products/Debug"
            / f"{APP_NAME}.app/Contents/PlugIns/ClaudeUsageTrackerTests.xctest"
        )
        if stale_xctest.exists():
            shutil.rmtree(str(stale_xctest))
            print("==> Removed stale xctest from DerivedData")

    print(f"==> Building {SCHEME}...")
    result = subprocess.run(
        [
            "xcodebuild",
            "-project", str(PROJECT_DIR / "code/ClaudeUsageTracker.xcodeproj"),
            "-scheme", SCHEME,
            "-destination", "platform=macOS",
            "-configuration", "Debug",
            "DEVELOPMENT_TEAM=C3WA2TT222",
            "-allowProvisioningUpdates",
            "build",
        ],
        capture_output=True,
        text=True,
    )
    lines = result.stdout.splitlines()
    for line in lines[-5:]:
        print(line)

    if result.returncode != 0:
        raise RuntimeError("Build failed.")

    # Find the built app
    if dd_dir is None:
        dd_dir = find_derived_data_dir()
    if dd_dir is None:
        raise RuntimeError("DerivedData not found after build.")

    build_app_path = dd_dir / "Build/Products/Debug" / f"{APP_NAME}.app"
    if not build_app_path.is_dir():
        raise RuntimeError(f"Built app not found at {build_app_path}")

    return build_app_path


def install_app(build_app_path: Path) -> None:
    """Atomic install: cp .new → verify → mv swap.

    If widget verification fails, .new is deleted and current app is untouched.
    """
    # Quit running instance
    subprocess.run(
        ["osascript", "-e", f'tell application "{APP_NAME}" to quit'],
        capture_output=True,
    )
    time.sleep(2)
    subprocess.run(["killall", APP_NAME], capture_output=True)
    time.sleep(0.5)

    print(f"==> Installing to {INSTALL_DIR}...")
    new_app = INSTALL_DIR / f"{APP_NAME}.app.new"

    # Clean up any leftover .new from a previous failed install
    if new_app.exists():
        shutil.rmtree(str(new_app))

    # Copy new build to .new (cp -R for clean copy; ditto can silently merge stale files)
    subprocess.run(["cp", "-R", str(build_app_path), str(new_app)], check=True)

    # Verify widget extension in .new (before touching current app)
    widget_appex = new_app / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
    if not widget_appex.is_dir():
        print("ERROR: Widget extension not found in new build.")
        print("       PlugIns contents:")
        plugins = new_app / "Contents/PlugIns"
        if plugins.exists():
            for p in plugins.iterdir():
                print(f"       {p.name}")
        else:
            print("       (no PlugIns directory)")
        shutil.rmtree(str(new_app))
        raise RuntimeError("Widget extension missing. New build deleted; current app untouched.")
    print(f"==> Widget extension verified: {widget_appex.name}")

    # Atomic swap: backup current → swap .new to current
    current_app = INSTALL_DIR / f"{APP_NAME}.app"
    if current_app.is_dir():
        current_version = get_app_version(str(current_app))
        app_backup_dir = APPGROUP_DIR / "app-backups"
        app_backup_dir.mkdir(parents=True, exist_ok=True)
        backup_app = app_backup_dir / f"{APP_NAME}.app.v{current_version}"
        print(f"==> Backing up current app to {backup_app}...")
        if backup_app.exists():
            shutil.rmtree(str(backup_app))
        # mv across filesystems falls back to copy+delete
        shutil.move(str(current_app), str(backup_app))

    new_app.rename(current_app)

    # Verify widget binary is fresh (not stale from previous install)
    widget_bin = (
        current_app / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        / "Contents/MacOS/ClaudeUsageTrackerWidgetExtension"
    )
    source_bin = (
        build_app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        / "Contents/MacOS/ClaudeUsageTrackerWidgetExtension"
    )
    if widget_bin.exists() and source_bin.exists():
        installed_mtime = widget_bin.stat().st_mtime
        source_mtime = source_bin.stat().st_mtime
        if installed_mtime < source_mtime:
            raise RuntimeError(
                f"Widget binary is stale!\n"
                f"       Installed: {datetime.fromtimestamp(installed_mtime)}\n"
                f"       Source:    {datetime.fromtimestamp(source_mtime)}\n"
                f"       The copy did not update the widget extension."
            )
        print(f"==> Widget binary timestamp verified: {datetime.fromtimestamp(installed_mtime)}")

    # Set bundle bit so Finder treats it as an app, not a folder
    subprocess.run(["SetFile", "-a", "B", str(current_app)], check=True)


def _verify_widget_deployment(app_path: str) -> None:
    """Deployment verification gate: prove widget registration is correct.

    Checks ALL known necessary conditions for widget operation after deploy.
    Raises RuntimeError if any condition fails. No WARNING — all failures stop deploy.
    """
    print("==> Running deployment verification gate...")
    passed = 0
    total = 3

    # --- Check 1: Widget found in pluginkit manifest ---
    pk = subprocess.run(
        ["pluginkit", "-m", "-v", "-i", WIDGET_ID],
        capture_output=True, text=True,
    )
    if WIDGET_ID not in pk.stdout:
        raise RuntimeError(
            f"GATE FAIL [1/3]: Widget not found in pluginkit\n"
            f"       {pk.stdout.strip()}"
        )
    passed += 1

    # --- Check 2: No DerivedData ghost in pluginkit ---
    if "DerivedData" in pk.stdout:
        raise RuntimeError(
            f"GATE FAIL [2/3]: Widget registered from DerivedData (ghost)\n"
            f"       {pk.stdout.strip()}"
        )
    passed += 1

    # --- Check 3: No ghost LS registration ---
    reg = dump_widget_registration(WIDGET_ID)
    if reg and "DerivedData" in reg:
        raise RuntimeError(
            f"GATE FAIL [3/3]: Ghost LS registration from DerivedData\n"
            f"       {reg}"
        )
    passed += 1

    print(f"==> Deployment verification gate: {passed}/{total} checks passed")


def check_lost_rows(current_db: str, backup_db: str) -> int:
    """Count rows in backup that are missing from current DB."""
    conn = sqlite3.connect(current_db)
    conn.execute(f"ATTACH '{backup_db}' AS backup")
    lost = conn.execute(
        "SELECT COUNT(*) FROM backup.usage_log "
        "WHERE rowid NOT IN (SELECT rowid FROM main.usage_log)"
    ).fetchone()[0]
    conn.close()
    return lost


def register_and_verify(backup_file: Path | None) -> None:
    """Register with LaunchServices, verify widget, check data integrity, launch."""
    # Verify bundle bit (Finder shows as folder without it)
    app_path = str(INSTALL_DIR / f"{APP_NAME}.app")
    result = subprocess.run(
        ["GetFileInfo", app_path], capture_output=True, text=True
    )
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if line.startswith("attributes:"):
                attrs = line.split(":", 1)[1].strip()
                if "B" not in attrs:
                    raise RuntimeError(
                        f"Bundle bit not set on {app_path}!\n"
                        f"       attributes: {attrs}\n"
                        f"       Finder will show it as a folder, not an app."
                    )
                print(f"==> Bundle bit verified: {attrs}")
                break

    # Deregister stale copies
    print("==> Cleaning stale LaunchServices registrations...")
    deregister_stale_apps(APP_NAME, str(DERIVED_DATA))

    # Verify entitlements before registration
    print("==> Verifying entitlements...")
    app_path_obj = Path(app_path)
    widget_appex = app_path_obj / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
    for target, name in [(app_path_obj, "main app"), (widget_appex, "widget extension")]:
        if not target.exists():
            continue
        ent_result = subprocess.run(
            ["codesign", "-d", "--entitlements", "-", str(target)],
            capture_output=True, text=True,
        )
        if "application-groups" not in ent_result.stdout:
            raise RuntimeError(
                f"Entitlements missing on {name}!\n"
                f"       Expected: com.apple.security.application-groups\n"
                f"       Widget will fail without App Group entitlement."
            )
    print("==> Entitlements verified: application-groups present on app and widget")

    # Register
    print(f"==> Registering {app_path} with LaunchServices...")
    register_app(app_path)
    pk_result = subprocess.run(
        ["pluginkit", "-e", "use", "-i", WIDGET_ID],
        capture_output=True, text=True,
    )
    if pk_result.returncode != 0:
        print(f"WARNING: pluginkit -e use failed (rc={pk_result.returncode}): {pk_result.stderr}")
    # Kill widget extension process first so chronod doesn't reuse the old binary
    subprocess.run(
        ["killall", "ClaudeUsageTrackerWidgetExtension"], capture_output=True
    )
    subprocess.run(["killall", "chronod"], capture_output=True)
    subprocess.run(["killall", "NotificationCenter"], capture_output=True)
    print("==> Killed widget extension + chronod + NotificationCenter")
    time.sleep(3)

    # Deployment verification gate (Layer 2: all conditions must pass)
    _verify_widget_deployment(app_path)

    # Data integrity check
    if backup_file and backup_file.exists() and APPGROUP_DB.exists():
        try:
            lost = check_lost_rows(str(APPGROUP_DB), str(backup_file))
        except sqlite3.Error as e:
            print(f"WARNING: Data integrity check failed: {e}")
            lost = -1

        if lost != 0:
            raise RuntimeError(
                f"FATAL: {lost} rows lost during deploy!\n"
                f"       Backup available: {backup_file}\n"
                f'       To restore: cp "{backup_file}" "{APPGROUP_DB}"\n'
                f"       Aborting launch. Investigate before restoring."
            )
        print(f"==> Data integrity verified: no rows lost (backup: {backup_file})")

    # Force Dock to refresh icon cache (prevents folder-icon bug)
    print("==> Refreshing Dock icon cache...")
    subprocess.run(["killall", "Dock"], capture_output=True)
    time.sleep(2)

    # Launch
    print("==> Launching...")
    subprocess.run(["open", app_path])


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # Find DerivedData
    dd_dir = find_derived_data_dir()
    if dd_dir is None:
        print("DerivedData not found. Building fresh...")

    # Phase 1: Backup + protected test
    _pre_count, backup_file = backup_database()

    with protect_files(APPGROUP_SETTINGS):
        with shelter_file(COOKIE_FILE):
            run_test_gate()
    # protect_files guarantees restore even if run_test_gate raises

    # Phase 2: Build (after test passes, after files are restored)
    print("==> Deregistering DerivedData from LaunchServices...")
    deregister_stale_apps(APP_NAME, str(DERIVED_DATA))

    build_app_path = build_app()

    # Phase 3: Atomic install + register + verify
    install_app(build_app_path)
    register_and_verify(backup_file)

    print("==> Done.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
