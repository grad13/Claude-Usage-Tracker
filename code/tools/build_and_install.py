#!/usr/bin/env python3
# meta: updated=2026-04-25 14:55 checked=-
"""Build, test, and install ClaudeUsageTracker.

Replaces build-and-install.sh with proper error handling:
- try/finally for file protection (no more forgotten restore)
- Atomic install (cp .new → mv swap, never leaves broken app)
- Structured error handling instead of || true
"""

from __future__ import annotations

import os
import re
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
    cleanup_stale_lsregister,
    deregister_stale_apps,
    dump_widget_registration,
    register_app,
    widget_running_path,
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
WIDGET_EXTENSION_NAME = "ClaudeUsageTrackerWidgetExtension"
# README advertises macOS 14.0+. Every bundled Mach-O binary's LC_BUILD_VERSION
# minos must stay <= this, or dyld refuses to load it on older Macs (the shared
# framework once shipped at minos 26.2, which kept the widget from launching on
# end-user machines).
ADVERTISED_MIN_OS = (14, 0)


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


def cleanup_stale_derived_data() -> None:
    """Delete DerivedData directories whose WorkspacePath does not match PROJECT_DIR.

    Walks DERIVED_DATA / "{APP_NAME}-*", reads info.plist → WorkspacePath.
    If WorkspacePath does not contain str(PROJECT_DIR), deletes the directory.
    Directories without info.plist are also deleted (orphaned).
    """
    if not DERIVED_DATA.exists():
        return
    import plistlib
    for d in DERIVED_DATA.iterdir():
        if not (d.is_dir() and d.name.startswith(f"{APP_NAME}-")):
            continue
        info_plist = d / "info.plist"
        if info_plist.exists():
            try:
                with open(info_plist, "rb") as f:
                    info = plistlib.load(f)
                workspace = info.get("WorkspacePath", "")
                if str(PROJECT_DIR) in workspace:
                    continue  # Current project — keep
                if not workspace:
                    print(f"WARNING: {d.name} has no WorkspacePath — deleting as orphan")
            except Exception:
                print(f"WARNING: Failed to read {info_plist} — skipping")
                continue
        else:
            print(f"WARNING: {d.name} has no info.plist — deleting as orphan")
        try:
            shutil.rmtree(d)
            print(f"  Deleted stale DerivedData: {d.name}")
        except Exception as e:
            print(f"WARNING: Failed to delete {d.name}: {e}")


def run_test_gate() -> None:
    """Run xcodebuild test. Raises on failure."""
    print("==> Running unit tests...")
    result = run(
        [
            "xcodebuild",
            "-project", str(PROJECT_DIR / "code/app/ClaudeUsageTracker.xcodeproj"),
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
            "-project", str(PROJECT_DIR / "code/app/ClaudeUsageTracker.xcodeproj"),
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


class GateFailure(RuntimeError):
    """Raised by individual gate functions on failure. Includes a label for
    diagnostics. Caught by `_verify_with_self_repair` for retry."""

    def __init__(self, label: str, detail: str):
        super().__init__(f"GATE FAIL [{label}]: {detail}")
        self.label = label
        self.detail = detail


def _gate_pluginkit(app_path: str) -> None:
    """Gate-1: pluginkit registers the widget exactly once, from /Applications."""
    pk = run(["pluginkit", "-m", "-v", "-i", WIDGET_ID],
             on_error="warn", label="pluginkit manifest")
    if WIDGET_ID not in pk.stdout:
        raise GateFailure("1/5 pluginkit",
                          f"Widget not found\n       {pk.stdout.strip()}")
    expected_appex = f"{app_path}/Contents/PlugIns/{WIDGET_EXTENSION_NAME}.appex"
    if expected_appex not in pk.stdout:
        raise GateFailure(
            "1/5 pluginkit",
            f"Widget registered from unexpected path\n"
            f"       expected: {expected_appex}\n"
            f"       stdout:   {pk.stdout.strip()}"
        )
    if "DerivedData" in pk.stdout or "/build/" in pk.stdout:
        raise GateFailure(
            "1/5 pluginkit",
            f"Widget registered from DerivedData/build ghost\n"
            f"       {pk.stdout.strip()}"
        )


def _repair_pluginkit(app_path: str) -> None:
    """Repair Gate-1: cleanup ghosts then re-add /Applications appex."""
    cleanup_stale_lsregister(APP_NAME, INSTALL_DIR)
    expected_appex = f"{app_path}/Contents/PlugIns/{WIDGET_EXTENSION_NAME}.appex"
    run(["pluginkit", "-a", expected_appex],
        on_error="warn", label="pluginkit -a")
    run(["pluginkit", "-e", "use", "-i", WIDGET_ID],
        on_error="warn", label="pluginkit enable")


def _gate_lsregister(app_path: str) -> None:
    """Gate-2: lsregister has the main `.app` only at /Applications.

    Scope is intentionally narrow:
      - Only `/ClaudeUsageTracker.app` paths are checked. Multiple .app
        registrations confuse Finder (folder-display bug, ambiguous launch).
      - `.appex` widget paths are NOT checked here — chronod resolves widgets
        through pluginkit (Gate-1) and the runtime path (Gate-5), and
        `lsregister -u` cannot reliably remove a freshly-built DerivedData
        appex (returns rc=1 with spotlight scan errors).

    A ghost path that no longer exists on disk is treated as harmless
    (LaunchServices will GC it; nothing on disk for Finder to launch).
    """
    result = run([LSREGISTER, "-dump"], on_error="warn", label="lsregister -dump")
    live_ghosts: list[str] = []
    dead_ghosts: list[str] = []
    for line in result.stdout.splitlines():
        m = re.match(r"^path:\s+(.+?)(?:\s+\(0x[0-9a-fA-F]+\))?\s*$", line)
        if not m:
            continue
        path = m.group(1)
        # Only the main .app — skip plugin extensions
        if not path.endswith(f"/{APP_NAME}.app"):
            continue
        if path == app_path:
            continue
        if Path(path).exists():
            live_ghosts.append(path)
        else:
            dead_ghosts.append(path)
    if dead_ghosts:
        print(f"==> Gate 2/5: ignoring {len(dead_ghosts)} dead ghost(s) "
              f"(LS still references deleted path)")
    if live_ghosts:
        raise GateFailure(
            "2/5 lsregister",
            "Live ghost main-app registrations remain:\n       "
            + "\n       ".join(live_ghosts)
        )


def _repair_lsregister(app_path: str) -> None:
    """Repair Gate-2: same as Gate-1 cleanup."""
    cleanup_stale_lsregister(APP_NAME, INSTALL_DIR)


_FINDERINFO_BUNDLE_BIT_BYTE = 8
_FINDERINFO_BUNDLE_BIT_MASK = 0x20  # bit 13 of the big-endian flags field


def _gate_finderinfo(app_path: str) -> None:
    """Gate-3: com.apple.FinderInfo has the bundle bit set so Finder treats
    the .app as a bundle (not a folder)."""
    result = run(["xattr", "-px", "com.apple.FinderInfo", app_path],
                 on_error="warn", label="xattr FinderInfo")
    if result.returncode != 0:
        # Missing xattr is OK — Finder will use the .app extension. But on
        # some systems with corrupted FinderInfo this is the symptom.
        return
    # Output is hex bytes, e.g. "00 00 00 00 00 00 00 00 20 00 ..."
    tokens = result.stdout.split()
    if len(tokens) <= _FINDERINFO_BUNDLE_BIT_BYTE:
        raise GateFailure(
            "3/5 finderinfo",
            f"FinderInfo too short ({len(tokens)} bytes)\n"
            f"       output: {result.stdout!r}"
        )
    try:
        flags_byte = int(tokens[_FINDERINFO_BUNDLE_BIT_BYTE], 16)
    except ValueError:
        raise GateFailure(
            "3/5 finderinfo",
            f"FinderInfo unparseable\n       output: {result.stdout!r}"
        )
    if not (flags_byte & _FINDERINFO_BUNDLE_BIT_MASK):
        raise GateFailure(
            "3/5 finderinfo",
            f"Bundle bit (0x{_FINDERINFO_BUNDLE_BIT_MASK:02x}) not set in flags "
            f"byte 0x{flags_byte:02x}\n       output: {result.stdout!r}"
        )


def _repair_finderinfo(app_path: str) -> None:
    """Repair Gate-3: delete FinderInfo so Finder rebuilds it on next access."""
    run(["xattr", "-d", "com.apple.FinderInfo", app_path],
        on_error="warn", label="xattr -d FinderInfo")
    # Re-set bundle bit explicitly to short-circuit Finder rebuild
    run(["SetFile", "-a", "B", app_path], on_error="warn", label="SetFile B")


def _gate_smoke_launch(app_path: str) -> None:
    """Gate-4: `open` launches the app and a process from the install path
    appears within 3 seconds."""
    expected_bin = f"{app_path}/Contents/MacOS/{APP_NAME}"
    # Make sure no prior instance is masking the test.
    run(["killall", APP_NAME], on_error="warn", label="killall pre-smoke")
    time.sleep(0.5)
    open_result = run(["open", app_path], on_error="warn", label="open smoke")
    if open_result.returncode != 0:
        raise GateFailure(
            "4/5 smoke",
            f"`open` returned {open_result.returncode}\n"
            f"       stderr: {open_result.stderr.strip()}"
        )
    # Wait for the process to appear
    deadline = time.monotonic() + 3.0
    seen_path: str | None = None
    while time.monotonic() < deadline:
        time.sleep(0.3)
        ps = run(["pgrep", "-fl", expected_bin],
                 on_error="warn", label="pgrep smoke")
        if ps.stdout.strip():
            # First token is PID, rest is the command path
            parts = ps.stdout.split(None, 1)
            seen_path = parts[1].strip() if len(parts) == 2 else ""
            break
    # Cleanup the smoke-test process regardless
    run(["killall", APP_NAME], on_error="warn", label="killall post-smoke")
    if seen_path is None:
        raise GateFailure(
            "4/5 smoke",
            f"App did not start within 3s after `open`\n"
            f"       expected binary: {expected_bin}"
        )
    if not seen_path.startswith(expected_bin):
        raise GateFailure(
            "4/5 smoke",
            f"App started from wrong path\n"
            f"       expected: {expected_bin}\n"
            f"       actual:   {seen_path}"
        )


def _repair_smoke_launch(app_path: str) -> None:
    """Repair Gate-4: aggressive cleanup of all caches that affect Finder/LS.
    No silver bullet, but the symptoms we've seen cluster around stale
    registrations and Finder cache."""
    cleanup_stale_lsregister(APP_NAME, INSTALL_DIR)
    register_app(app_path)
    run(["killall", "Finder"], on_error="warn", label="killall Finder")
    run(["killall", "Dock"], on_error="warn", label="killall Dock")
    time.sleep(2)


def _gate_widget_runtime_path(app_path: str) -> None:
    """Gate-5 (best effort): if the widget extension is currently running,
    it must be launched from /Applications (not DerivedData/build)."""
    actual = widget_running_path(WIDGET_EXTENSION_NAME)
    if actual is None:
        # No running process — chronod will resolve from pluginkit when next
        # render is triggered. Gates 1+2 already verified that resolution.
        print("==> Gate-5 widget-runtime: no running widget process (skip)")
        return
    expected_prefix = f"{app_path}/Contents/PlugIns/{WIDGET_EXTENSION_NAME}.appex"
    if not actual.startswith(expected_prefix):
        raise GateFailure(
            "5/5 widget-runtime",
            f"Widget extension running from wrong path\n"
            f"       expected prefix: {expected_prefix}\n"
            f"       actual:          {actual}"
        )


def _repair_widget_runtime_path(app_path: str) -> None:
    """Repair Gate-5: clean ghosts + kill widget chain so chronod re-resolves
    against pluginkit (which Gate-1 already verified is /Applications)."""
    cleanup_stale_lsregister(APP_NAME, INSTALL_DIR)
    for proc in [WIDGET_EXTENSION_NAME, "chronod", "NotificationCenter"]:
        run(["killall", proc], on_error="warn", label=f"killall {proc}")
    time.sleep(5)


def _verify_with_self_repair(
    label: str,
    gate: callable,
    repair: callable,
    app_path: str,
) -> None:
    """Run a gate. On failure, attempt one round of self-repair and re-run.
    If the second attempt fails, raise the original GateFailure to abort deploy.
    """
    try:
        gate(app_path)
        print(f"==> Gate {label}: PASS")
        return
    except GateFailure as e:
        print(f"==> Gate {label}: FAIL — attempting self-repair")
        print(f"    detail: {e.detail}")
        try:
            repair(app_path)
        except Exception as repair_err:
            print(f"    repair raised: {repair_err}")
        try:
            gate(app_path)
            print(f"==> Gate {label}: PASS after repair")
            return
        except GateFailure as e2:
            raise RuntimeError(
                f"GATE FAIL after self-repair [{label}]: {e2.detail}"
            ) from e2


def _verify_widget_deployment(app_path: str) -> None:
    """Run all 5 deployment verification gates with self-repair.

    Each gate represents a known failure mode previously fixed by hand
    (DerivedData widget ghost, Finder folder display, lsregister bloat).
    A single retry per gate is allowed after automatic repair; persistent
    failure aborts the deploy.
    """
    print("==> Running deployment verification gates...")
    gates: list[tuple[str, callable, callable]] = [
        ("1/5 pluginkit",       _gate_pluginkit,            _repair_pluginkit),
        ("2/5 lsregister",      _gate_lsregister,           _repair_lsregister),
        ("3/5 finderinfo",      _gate_finderinfo,           _repair_finderinfo),
        ("4/5 smoke",           _gate_smoke_launch,         _repair_smoke_launch),
        ("5/5 widget-runtime",  _gate_widget_runtime_path,  _repair_widget_runtime_path),
    ]
    for label, gate, repair in gates:
        _verify_with_self_repair(label, gate, repair, app_path)
    print("==> Deployment verification gates: 5/5 passed")



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
    # sole registered source (prevents widget loading from wrong location).
    # cleanup_stale_lsregister catches DerivedData, build/, xcarchive/, export/
    # paths in one pass — broader than the legacy deregister_stale_apps glob.
    print("==> Cleaning stale LaunchServices registrations...")
    n_removed = cleanup_stale_lsregister(APP_NAME, INSTALL_DIR)
    if n_removed:
        print(f"    removed {n_removed} ghost registration(s)")
    deregister_stale_apps(APP_NAME, str(DERIVED_DATA))  # belt-and-suspenders

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


# Mach-O magic numbers (thin 32/64-bit, both byte orders, and fat/universal).
_MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",  # 32-bit
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",  # 64-bit
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",  # fat / universal
}


def _is_macho(path: str) -> bool:
    """True if the file starts with a Mach-O magic number. Used to skip the
    many non-binary bundle resources (plists, .car, signatures) so vtool is
    only invoked on actual binaries (no spurious 'not a Mach-O' warnings)."""
    try:
        with open(path, "rb") as fh:
            return fh.read(4) in _MACHO_MAGICS
    except OSError:
        return False


def _macho_minos(path: str) -> tuple[int, int] | None:
    """Return (major, minor) of a Mach-O binary's LC_BUILD_VERSION minos.

    Returns None for anything that isn't a Mach-O binary (vtool exits non-zero)
    or whose build version can't be parsed. Uses `vtool -show-build`, which
    reports the load command directly without a full otool dump.
    """
    res = run(["vtool", "-show-build", path], on_error="warn", label="vtool minos")
    if res.returncode != 0:
        return None
    for line in res.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "minos":
            try:
                nums = [int(x) for x in parts[1].split(".")]
            except ValueError:
                return None
            return (nums[0], nums[1] if len(nums) > 1 else 0)
    return None


def verify_min_os(app_path: str) -> None:
    """Fail the deploy if any bundled Mach-O binary's minos exceeds the
    advertised macOS minimum (14.0).

    Catches accidental Xcode SDK auto-bumps (e.g. the shared framework drifting
    to minos 26.2) before they ship — such a binary loads on the developer's
    newer Mac but dyld refuses it on older end-user Macs, so the widget never
    appears. This is a build-config invariant, not a self-repairable runtime
    state, so it lives outside the 5-gate self-repair pipeline.
    """
    app = Path(app_path)
    adv = f"{ADVERTISED_MIN_OS[0]}.{ADVERTISED_MIN_OS[1]}"
    offenders: list[str] = []
    for f in sorted(app.rglob("*")):
        if f.is_dir() or f.is_symlink() or not _is_macho(str(f)):
            continue
        minos = _macho_minos(str(f))
        if minos is not None and minos > ADVERTISED_MIN_OS:
            offenders.append(f"{f.relative_to(app)} (minos {minos[0]}.{minos[1]})")
    if offenders:
        raise RuntimeError(
            f"Min-OS gate FAIL: {len(offenders)} bundled binary(ies) exceed "
            f"advertised macOS {adv}:\n       " + "\n       ".join(offenders)
            + "\n       dyld will refuse to load these on Macs older than that "
            "version (widget will not launch). Lower MACOSX_DEPLOYMENT_TARGET."
        )
    print(f"==> Min-OS gate verified: all bundled binaries minos <= {adv}")


def verify_deployment(app_path: str) -> None:
    """Deployment verification gate (all conditions must pass)."""
    _verify_widget_deployment(app_path)
    verify_min_os(app_path)


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
    print("==> Cleaning up stale DerivedData...")
    cleanup_stale_derived_data()
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
