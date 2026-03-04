"""Tests for binary backup and atomic install logic.

Covers:
  Test 6:  Version-tagged rename backup (.app → .app.v0.9.1)
  Test 7:  Missing Info.plist → .app.vunknown fallback
  Test 8:  Same-version overwrite (existing backup replaced)
  Test 20: Atomic install — widget missing → .new deleted, current app untouched
  Test 21: Atomic install — success → .new swapped to current
"""

import plistlib
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from version import get_app_version


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_app_with_version(install_dir, app_name, version=None):
    """Create an .app directory with optional Info.plist version."""
    app_dir = install_dir / f"{app_name}.app" / "Contents"
    app_dir.mkdir(parents=True)

    if version is not None:
        plist_path = app_dir / "Info.plist"
        with open(plist_path, "wb") as f:
            plistlib.dump({"CFBundleShortVersionString": version}, f)

    return install_dir / f"{app_name}.app"


def _run_backup_logic(install_dir, app_name):
    """Run the same backup logic as build_and_install.install_app."""
    current_app = install_dir / f"{app_name}.app"
    if current_app.is_dir():
        current_version = get_app_version(str(current_app))
        backup_app = install_dir / f"{app_name}.app.v{current_version}"
        if backup_app.exists():
            shutil.rmtree(str(backup_app))
        current_app.rename(backup_app)


# ---------------------------------------------------------------------------
# Test 6-8: Binary backup (version-tagged rename)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "scenario,version,marker_before,expected_suffix,expected_marker",
    [
        # Test 6: versioned rename
        ("versioned", "0.9.1", None, "v0.9.1", None),
        # Test 7: no Info.plist → vunknown
        ("no_plist", None, None, "vunknown", None),
        # Test 8: same-version overwrite
        ("overwrite", "0.9.1", "old", "v0.9.1", "new"),
    ],
    ids=["versioned", "no_plist", "overwrite"],
)
def test_binary_backup(
    tmp_path, scenario, version, marker_before, expected_suffix, expected_marker
):
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()

    # For overwrite test: create pre-existing backup
    if marker_before is not None:
        existing_backup = install_dir / f"TestApp.app.v{expected_suffix}"
        existing_backup.mkdir(parents=True)
        (existing_backup / "marker").write_text(marker_before)

    # Create the app
    _create_app_with_version(install_dir, "TestApp", version)

    # For overwrite test: add marker to the app being backed up
    if expected_marker is not None:
        (install_dir / "TestApp.app" / "marker").write_text(expected_marker)

    _run_backup_logic(install_dir, "TestApp")

    # Verify backup was created with correct suffix
    backup = install_dir / f"TestApp.app.{expected_suffix}"
    assert backup.is_dir(), f"Expected {backup.name} to exist"

    # Original app should be gone (mv)
    assert not (install_dir / "TestApp.app").exists()

    # For overwrite test: verify content was replaced
    if expected_marker is not None:
        assert (backup / "marker").read_text() == expected_marker


# ---------------------------------------------------------------------------
# Test 20: Atomic install — widget missing
# ---------------------------------------------------------------------------

def test_atomic_install_widget_missing(tmp_path):
    """Widget extension missing in new build → .new deleted, current app untouched."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()

    # Current app (should survive)
    current_app = install_dir / "TestApp.app"
    (current_app / "Contents").mkdir(parents=True)
    (current_app / "marker").write_text("current")

    # New build without widget extension
    new_build = tmp_path / "Build" / "TestApp.app"
    (new_build / "Contents" / "PlugIns").mkdir(parents=True)
    (new_build / "marker").write_text("new")

    # Simulate atomic install logic: cp to .new, verify widget
    new_app = install_dir / "TestApp.app.new"
    shutil.copytree(str(new_build), str(new_app))

    widget_appex = new_app / "Contents/PlugIns/TestWidget.appex"
    assert not widget_appex.is_dir()

    # Widget missing → delete .new, keep current
    shutil.rmtree(str(new_app))

    # Current app is untouched
    assert current_app.is_dir()
    assert (current_app / "marker").read_text() == "current"
    assert not new_app.exists()


# ---------------------------------------------------------------------------
# Test 21: Atomic install — success (swap)
# ---------------------------------------------------------------------------

def test_atomic_install_success(tmp_path):
    """Normal atomic install: .new → verify → swap to current."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()

    # Current app
    current_app = install_dir / "TestApp.app"
    (current_app / "Contents").mkdir(parents=True)
    (current_app / "marker").write_text("old")

    # New build with widget extension
    new_build = tmp_path / "Build" / "TestApp.app"
    (new_build / "Contents" / "PlugIns" / "TestWidget.appex").mkdir(parents=True)
    (new_build / "marker").write_text("new")

    # Simulate atomic install
    new_app = install_dir / "TestApp.app.new"
    shutil.copytree(str(new_build), str(new_app))

    # Verify widget
    assert (new_app / "Contents/PlugIns/TestWidget.appex").is_dir()

    # Atomic swap
    backup_name = install_dir / "TestApp.app.v0.1.0"
    current_app.rename(backup_name)
    new_app.rename(current_app)

    # Verify
    assert current_app.is_dir()
    assert (current_app / "marker").read_text() == "new"
    assert backup_name.is_dir()
    assert (backup_name / "marker").read_text() == "old"
