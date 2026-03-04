#!/usr/bin/env python3
"""Rollback ClaudeUsageTracker to a previous version.

Atomic swap: cp .new → mv swap (never leaves broken app in /Applications).
Data (DB, cookies) is not affected.

Usage:
    python3 rollback.py <version>
    python3 rollback.py v0.9.1
"""

import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "lib"))

from launchservices import LSREGISTER, register_app

APP_NAME = os.environ.get("APP_NAME", "ClaudeUsageTracker")
INSTALL_DIR = Path(os.environ.get("INSTALL_DIR", "/Applications"))


def list_versions() -> list[str]:
    """List available backup versions."""
    versions = []
    for d in sorted(INSTALL_DIR.glob(f"{APP_NAME}.app.v*")):
        if d.is_dir():
            versions.append(d.name.removeprefix(f"{APP_NAME}.app."))
    return versions


def rollback(version: str, *, test_mode: bool = False) -> None:
    """Rollback to a specific version using atomic swap."""
    backup_app = INSTALL_DIR / f"{APP_NAME}.app.{version}"
    if not backup_app.is_dir():
        raise RuntimeError(f"{backup_app} not found")

    # Check write permission
    test_file = INSTALL_DIR / ".rollback_test"
    try:
        test_file.touch()
        test_file.unlink()
    except PermissionError:
        raise RuntimeError(f"Cannot write to {INSTALL_DIR} — run with sudo or check permissions")

    # Quit running app
    if not test_mode:
        print(f"==> Quitting {APP_NAME}...")
        subprocess.run(
            ["osascript", "-e", f'tell application "{APP_NAME}" to quit'],
            capture_output=True,
        )
        time.sleep(2)
        subprocess.run(["killall", APP_NAME], capture_output=True)
        time.sleep(0.5)

    # Atomic swap: cp .new → mv swap
    print(f"==> Restoring {version}...")
    current_app = INSTALL_DIR / f"{APP_NAME}.app"
    new_app = INSTALL_DIR / f"{APP_NAME}.app.new"
    removing_app = INSTALL_DIR / f"{APP_NAME}.app.removing"

    # Clean up any leftover temp dirs
    if new_app.exists():
        shutil.rmtree(str(new_app))
    if removing_app.exists():
        shutil.rmtree(str(removing_app))

    shutil.copytree(str(backup_app), str(new_app))

    if current_app.is_dir():
        current_app.rename(removing_app)
    new_app.rename(current_app)
    if removing_app.exists():
        shutil.rmtree(str(removing_app))

    if not test_mode:
        print("==> Registering with LaunchServices...")
        register_app(str(current_app))

        print("==> Launching...")
        subprocess.run(["open", str(current_app)])

    print(f"==> Rollback to {version} complete.")
    print("    Data (DB, Cookie) は変更されていません。")


def main() -> None:
    if len(sys.argv) < 2:
        print("Available versions:")
        for v in list_versions():
            print(f"  {v}")
        print(f"\nUsage: {sys.argv[0]} <version>")
        print(f"Example: {sys.argv[0]} v0.9.1")
        sys.exit(1)

    version = sys.argv[1]
    test_mode = bool(os.environ.get("ROLLBACK_TEST_MODE"))
    rollback(version, test_mode=test_mode)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
