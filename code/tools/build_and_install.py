#!/usr/bin/env python3
"""Build, test, and install ClaudeUsageTracker.

Replaces build-and-install.sh with proper error handling:
- try/finally for file protection (no more forgotten restore)
- Atomic install (cp .new → mv swap, never leaves broken app)
- Structured error handling instead of || true
"""

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

from data_protection import protect_files
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

    # Rotate: keep newest 10
    backups = sorted(backup_dir.glob("usage_*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in backups[10:]:
        old.unlink()

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
    """Build the app and return the path to the built .app."""
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

    # Copy new build to .new (ditto preserves macOS metadata including bundle bit)
    subprocess.run(["ditto", str(build_app_path), str(new_app)], check=True)

    # Remove test bundle from .new
    test_xctest = new_app / "Contents/PlugIns/ClaudeUsageTrackerTests.xctest"
    if test_xctest.exists():
        shutil.rmtree(str(test_xctest))

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


def register_and_verify(backup_file: Path | None) -> None:
    """Register with LaunchServices, verify widget, check data integrity, launch."""
    # Deregister stale copies
    print("==> Cleaning stale LaunchServices registrations...")
    deregister_stale_apps(APP_NAME, str(DERIVED_DATA))

    # Register
    app_path = str(INSTALL_DIR / f"{APP_NAME}.app")
    print(f"==> Registering {app_path} with LaunchServices...")
    register_app(app_path)
    subprocess.run(["pluginkit", "-e", "use", "-i", WIDGET_ID], capture_output=True)
    subprocess.run(["killall", "chronod"], capture_output=True)
    time.sleep(3)

    # Verify widget registration
    print("==> Verifying widget extension registration...")
    widget_reg = dump_widget_registration(WIDGET_ID)
    if widget_reg and "DerivedData" in widget_reg:
        raise RuntimeError(
            f"Widget extension still registered from DerivedData!\n"
            f"       {widget_reg}\n"
            f"       chronod will fail to launch the widget from /Applications."
        )
    if widget_reg and "/Applications/" in widget_reg:
        print(f"==> Widget registered correctly: {widget_reg}")
    else:
        print(f"WARNING: Could not verify widget registration path: {widget_reg}")

    # Data integrity check
    if backup_file and backup_file.exists() and APPGROUP_DB.exists():
        try:
            conn = sqlite3.connect(str(APPGROUP_DB))
            conn.execute(f"ATTACH '{backup_file}' AS backup")
            lost = conn.execute(
                "SELECT COUNT(*) FROM backup.usage_log "
                "WHERE rowid NOT IN (SELECT rowid FROM main.usage_log)"
            ).fetchone()[0]
            conn.close()
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

    with protect_files(APPGROUP_SETTINGS, COOKIE_FILE):
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
