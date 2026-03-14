# Supplement for: tests/tools/test_version.py
"""Supplementary tests for lib/version.py.

Covers missing cases from spec (docs/spec/tools/version.md):
  - VR-03: Info.plist is invalid binary (plistlib.InvalidFileException)
  - VR-04: CFBundleShortVersionString key missing from plist
  - VR-05: Unexpected exception (PermissionError) + WARNING to stderr
  - VR-06: app_path passed as str type
"""

import plistlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from version import get_app_version


@pytest.fixture
def app_dir(tmp_path):
    """Create a TestApp.app directory structure with Contents/."""
    app = tmp_path / "TestApp.app" / "Contents"
    app.mkdir(parents=True)
    return tmp_path / "TestApp.app"


def test_invalid_plist_binary_returns_unknown(app_dir):
    """VR-03: Info.plist that is not a valid plist returns 'unknown' silently."""
    plist_path = app_dir / "Contents" / "Info.plist"
    plist_path.write_bytes(b"\x00\x01\x02corrupt-not-a-plist")

    assert get_app_version(app_dir) == "unknown"


def test_missing_version_key_returns_unknown(app_dir):
    """VR-04: Valid plist without CFBundleShortVersionString returns 'unknown'."""
    plist_path = app_dir / "Contents" / "Info.plist"
    with open(plist_path, "wb") as f:
        plistlib.dump({"CFBundleName": "TestApp"}, f)

    assert get_app_version(app_dir) == "unknown"


def test_unexpected_exception_warns_stderr(app_dir, capsys):
    """VR-05: PermissionError prints WARNING to stderr and returns 'unknown'."""
    plist_path = app_dir / "Contents" / "Info.plist"
    plist_path.write_text("dummy")
    plist_path.chmod(0o000)

    try:
        result = get_app_version(app_dir)
        captured = capsys.readouterr()

        assert result == "unknown"
        assert "WARNING" in captured.err
    finally:
        # Restore permissions for tmp_path cleanup
        plist_path.chmod(0o644)


def test_str_path_accepted(app_dir):
    """VR-06: app_path as str type works correctly."""
    plist_path = app_dir / "Contents" / "Info.plist"
    with open(plist_path, "wb") as f:
        plistlib.dump({"CFBundleShortVersionString": "2.0.0"}, f)

    # Pass str instead of Path
    assert get_app_version(str(app_dir)) == "2.0.0"
