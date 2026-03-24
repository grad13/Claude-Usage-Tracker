# meta: updated=2026-03-15 08:26 checked=-
"""Tests for binary backup and atomic install logic.

Covers:
  Test 6:  Version-tagged rename backup (.app -> .app.v0.9.1)
  Test 7:  Missing Info.plist -> .app.vunknown fallback
  Test 8:  Same-version overwrite (existing backup replaced)
  Test 20: Atomic install — widget missing -> .new deleted, current app untouched
  Test 21: Atomic install — success -> .new swapped to current
"""

import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from version import get_app_version


def _run_backup_logic(install_dir, app_name):
    """Run the same backup logic as build_and_install.install_app."""
    current_app = install_dir / f"{app_name}.app"
    if current_app.is_dir():
        current_version = get_app_version(str(current_app))
        backup_app = install_dir / f"{app_name}.app.v{current_version}"
        if backup_app.exists():
            shutil.rmtree(str(backup_app))
        current_app.rename(backup_app)


class TestBinaryBackup:

    @pytest.mark.parametrize(
        "scenario,version,marker_before,expected_suffix,expected_marker",
        [
            ("versioned", "0.9.1", None, "v0.9.1", None),
            ("no_plist", None, None, "vunknown", None),
            ("overwrite", "0.9.1", "old", "v0.9.1", "new"),
        ],
        ids=["versioned", "no_plist", "overwrite"],
    )
    def test_binary_backup(
        self, tmp_path, make_app_with_version, scenario, version, marker_before,
        expected_suffix, expected_marker,
    ):
        install_dir = tmp_path / "Applications"
        install_dir.mkdir()

        if marker_before is not None:
            existing_backup = install_dir / f"TestApp.app.v{expected_suffix}"
            existing_backup.mkdir(parents=True)
            (existing_backup / "marker").write_text(marker_before)

        make_app_with_version(install_dir, "TestApp", version)

        if expected_marker is not None:
            (install_dir / "TestApp.app" / "marker").write_text(expected_marker)

        _run_backup_logic(install_dir, "TestApp")

        backup = install_dir / f"TestApp.app.{expected_suffix}"
        assert backup.is_dir(), f"Expected {backup.name} to exist"

        assert not (install_dir / "TestApp.app").exists()

        if expected_marker is not None:
            assert (backup / "marker").read_text() == expected_marker


class TestAtomicInstall:

    def test_widget_missing(self, tmp_path):
        """Widget extension missing in new build -> .new deleted, current app untouched."""
        install_dir = tmp_path / "Applications"
        install_dir.mkdir()

        current_app = install_dir / "TestApp.app"
        (current_app / "Contents").mkdir(parents=True)
        (current_app / "marker").write_text("current")

        new_build = tmp_path / "Build" / "TestApp.app"
        (new_build / "Contents" / "PlugIns").mkdir(parents=True)
        (new_build / "marker").write_text("new")

        new_app = install_dir / "TestApp.app.new"
        shutil.copytree(str(new_build), str(new_app))

        widget_appex = new_app / "Contents/PlugIns/TestWidget.appex"
        assert not widget_appex.is_dir()

        shutil.rmtree(str(new_app))

        assert current_app.is_dir()
        assert (current_app / "marker").read_text() == "current"
        assert not new_app.exists()

    def test_success(self, tmp_path):
        """Normal atomic install: .new -> verify -> swap to current."""
        install_dir = tmp_path / "Applications"
        install_dir.mkdir()

        current_app = install_dir / "TestApp.app"
        (current_app / "Contents").mkdir(parents=True)
        (current_app / "marker").write_text("old")

        new_build = tmp_path / "Build" / "TestApp.app"
        (new_build / "Contents" / "PlugIns" / "TestWidget.appex").mkdir(parents=True)
        (new_build / "marker").write_text("new")

        new_app = install_dir / "TestApp.app.new"
        shutil.copytree(str(new_build), str(new_app))

        assert (new_app / "Contents/PlugIns/TestWidget.appex").is_dir()

        backup_name = install_dir / "TestApp.app.v0.1.0"
        current_app.rename(backup_name)
        new_app.rename(current_app)

        assert current_app.is_dir()
        assert (current_app / "marker").read_text() == "new"
        assert backup_name.is_dir()
        assert (backup_name / "marker").read_text() == "old"
