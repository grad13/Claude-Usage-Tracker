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
import sys
import time
from datetime import datetime
from pathlib import Path

# Add lib/ to path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from data_protection import protect_files, shelter_file
from db_backup import backup_database, check_lost_rows
from launchservices import (
    LSREGISTER,
    deregister_stale_apps,
    dump_widget_registration,
    register_app,
)
from runner import run
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
    """Find the DerivedData directory for THIS project.

    Multiple DerivedData dirs may exist (e.g., ClaudeUsageTracker-xxx,
    ClaudeUsageTracker-yyy). Each has info.plist with WorkspacePath.
    We match against our PROJECT_DIR to find the correct one.
    """
    if not DERIVED_DATA.exists():
        return None
    candidates = []
    for d in DERIVED_DATA.iterdir():
        if not (d.is_dir() and d.name.startswith(f"{APP_NAME}-")):
            continue
        # Check info.plist for WorkspacePath
        info_plist = d / "info.plist"
        if info_plist.exists():
            import plistlib
            try:
                with open(info_plist, "rb") as f:
                    info = plistlib.load(f)
                workspace = info.get("WorkspacePath", "")
                if str(PROJECT_DIR) in workspace:
                    return d  # Exact match
            except Exception:
                pass
        candidates.append(d)
    # No match found — fresh build will create a new DerivedData
    if candidates:
        print(f"WARNING: {len(candidates)} DerivedData dir(s) found but none match "
              f"PROJECT_DIR={PROJECT_DIR}. Will build fresh.")
    return None



def run_test_gate() -> None:
    """Run xcodebuild test. Raises on failure."""
    print("==> Running unit tests...")
    result = run(
        [
            "xcodebuild",
            "-project", str(PROJECT_DIR / "code/ClaudeUsageTracker.xcodeproj"),
            "-scheme", SCHEME,
            "-destination", "platform=macOS",
            "DEVELOPMENT_TEAM=C3WA2TT222",
            "-allowProvisioningUpdates",
            "test",
        ],
        on_error="warn",
        label="xcodebuild test",
    )
    # Show last 5 lines of output
    for line in result.stdout.splitlines()[-5:]:
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
    result = run(
        [
            "xcodebuild",
            "-project", str(PROJECT_DIR / "code/ClaudeUsageTracker.xcodeproj"),
            "-scheme", SCHEME,
            "-destination", "platform=macOS",
            "-configuration", "Debug",
            "DEVELOPMENT_TEAM=C3WA2TT222",
            "-allowProvisioningUpdates",
            "clean", "build",
        ],
        on_error="warn",
        label="xcodebuild build",
    )
    for line in result.stdout.splitlines()[-5:]:
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


def quit_running_app() -> None:
    """Quit the running app instance gracefully, then force-kill."""
    run(["osascript", "-e", f'tell application "{APP_NAME}" to quit'],
        on_error="warn", label="quit app")
    # Wait for app to handle quit event and flush state (settings, cookies)
    time.sleep(2)
    run(["killall", APP_NAME], on_error="warn", label="killall app")
    # Wait for process to fully terminate before touching the .app bundle
    time.sleep(0.5)


def install_app(build_app_path: Path) -> None:
    """Atomic install: cp .new → verify widget → backup current → mv swap.

    If widget verification fails, .new is deleted and current app is untouched.
    """
    print(f"==> Installing to {INSTALL_DIR}...")
    new_app = INSTALL_DIR / f"{APP_NAME}.app.new"

    # Clean up any leftover .new from a previous failed install
    if new_app.exists():
        shutil.rmtree(str(new_app))

    # Copy new build to .new (cp -R for clean copy; ditto can silently merge stale files)
    run(["cp", "-R", str(build_app_path), str(new_app)], label="cp to .new")

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


def verify_installed_widget(build_app_path: Path, installed_app: Path) -> None:
    """Verify installed widget binary matches the build and set bundle bit.

    Checks size and mtime to catch stale binaries from previous installs.
    """
    widget_bin = (
        installed_app / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        / "Contents/MacOS/ClaudeUsageTrackerWidgetExtension"
    )
    source_bin = (
        build_app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        / "Contents/MacOS/ClaudeUsageTrackerWidgetExtension"
    )
    if widget_bin.exists() and source_bin.exists():
        inst_stat = widget_bin.stat()
        src_stat = source_bin.stat()
        if inst_stat.st_size != src_stat.st_size:
            raise RuntimeError(
                f"Widget binary size mismatch!\n"
                f"       Installed: {inst_stat.st_size} bytes\n"
                f"       Source:    {src_stat.st_size} bytes"
            )
        if inst_stat.st_mtime < src_stat.st_mtime:
            raise RuntimeError(
                f"Widget binary is stale!\n"
                f"       Installed: {datetime.fromtimestamp(inst_stat.st_mtime)}\n"
                f"       Source:    {datetime.fromtimestamp(src_stat.st_mtime)}"
            )
        print(f"==> Widget binary verified: size={inst_stat.st_size}, "
              f"mtime={datetime.fromtimestamp(inst_stat.st_mtime)}")

    # Set bundle bit so Finder treats it as an app, not a folder
    run(["SetFile", "-a", "B", str(installed_app)], label="SetFile bundle bit")


def _verify_widget_deployment(app_path: str) -> None:
    """Deployment verification gate: prove widget registration is correct.

    Checks ALL known necessary conditions for widget operation after deploy.
    Raises RuntimeError if any condition fails. No WARNING — all failures stop deploy.
    """
    print("==> Running deployment verification gate...")
    passed = 0
    total = 3

    # --- Check 1: Widget found in pluginkit manifest ---
    pk = run(["pluginkit", "-m", "-v", "-i", WIDGET_ID],
             on_error="warn", label="pluginkit manifest")
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



def verify_bundle_bits(app_path: str) -> None:
    """Verify bundle bit is set (Finder shows as folder without it)."""
    result = run(["GetFileInfo", app_path], on_error="warn", label="GetFileInfo")
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


def register_and_clean(app_path: str) -> None:
    """Deregister stale copies, verify entitlements, register app, restart widget processes."""
    # Deregister DerivedData from LS after install so /Applications is the
    # sole registered source (prevents widget loading from wrong location)
    print("==> Cleaning stale LaunchServices registrations...")
    deregister_stale_apps(APP_NAME, str(DERIVED_DATA))

    # Verify entitlements before registration
    print("==> Verifying entitlements...")
    app_path_obj = Path(app_path)
    widget_appex = app_path_obj / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
    for target, name in [(app_path_obj, "main app"), (widget_appex, "widget extension")]:
        if not target.exists():
            continue
        ent_result = run(
            ["codesign", "-d", "--entitlements", "-", str(target)],
            label=f"codesign entitlements {name}",
        )
        if "application-groups" not in ent_result.stdout:
            raise RuntimeError(
                f"Entitlements missing on {name}!\n"
                f"       Expected: com.apple.security.application-groups\n"
                f"       stdout: {ent_result.stdout[:200]}\n"
                f"       stderr: {ent_result.stderr[:200]}"
            )
    print("==> Entitlements verified: application-groups present on app and widget")

    # Register
    print(f"==> Registering {app_path} with LaunchServices...")
    register_app(app_path)
    run(["pluginkit", "-e", "use", "-i", WIDGET_ID],
        on_error="warn", label="pluginkit enable")
    # Kill widget extension process first so chronod doesn't reuse the old binary
    for proc in ["ClaudeUsageTrackerWidgetExtension", "chronod", "NotificationCenter"]:
        run(["killall", proc], on_error="warn", label=f"killall {proc}")
    print("==> Killed widget extension + chronod + NotificationCenter")
    # Wait for OS to restart widget-related daemons (chronod, NC) with new binary
    time.sleep(3)


def verify_deployment(app_path: str) -> None:
    """Deployment verification gate (all conditions must pass)."""
    _verify_widget_deployment(app_path)


def check_data_integrity(backup_file: Path | None) -> None:
    """Check no rows were lost during deploy."""
    if not (backup_file and backup_file.exists() and APPGROUP_DB.exists()):
        return
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


def refresh_and_launch(app_path: str) -> None:
    """Force Dock refresh + launch app."""
    print("==> Refreshing Dock icon cache...")
    run(["killall", "Dock"], on_error="warn", label="killall Dock")
    # Wait for Dock to restart and rebuild icon cache with new app bundle
    time.sleep(2)

    print("==> Launching...")
    run(["open", app_path], label="launch app")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # Find DerivedData
    dd_dir = find_derived_data_dir()
    if dd_dir is None:
        print("DerivedData not found. Building fresh...")

    # Phase 1: Backup + protected test
    _pre_count, backup_file = backup_database(APPGROUP_DB, APPGROUP_DIR)

    with protect_files(APPGROUP_SETTINGS):
        with shelter_file(COOKIE_FILE):
            run_test_gate()
    # protect_files guarantees restore even if run_test_gate raises

    # Phase 2: Build (after test passes, after files are restored)
    # Deregister DerivedData from LS before build so xcodebuild doesn't
    # reuse stale code signature info from previous builds
    print("==> Deregistering DerivedData from LaunchServices...")
    deregister_stale_apps(APP_NAME, str(DERIVED_DATA))

    build_app_path = build_app()

    # Phase 3: Quit → Atomic install → Verify → Register → Launch
    quit_running_app()
    install_app(build_app_path)
    installed_app = INSTALL_DIR / f"{APP_NAME}.app"
    verify_installed_widget(build_app_path, installed_app)
    app_path = str(installed_app)
    verify_bundle_bits(app_path)
    register_and_clean(app_path)
    verify_deployment(app_path)
    check_data_integrity(backup_file)
    refresh_and_launch(app_path)

    print("==> Done.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
