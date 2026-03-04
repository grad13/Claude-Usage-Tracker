"""Tests for shared lib modules.

Covers:
  - lib/version.py: get_app_version (using plistlib, no PlistBuddy dependency)
  - lib/launchservices.py: deregister_stale_apps input validation
"""

import plistlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from version import get_app_version
from launchservices import deregister_stale_apps


# ---------------------------------------------------------------------------
# lib/version.py: get_app_version
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "version,expected",
    [
        ("1.2.3", "1.2.3"),
        (None, "unknown"),  # no Info.plist
    ],
    ids=["with_version", "no_plist"],
)
def test_get_app_version(tmp_path, version, expected):
    app_dir = tmp_path / "TestApp.app" / "Contents"
    app_dir.mkdir(parents=True)

    if version is not None:
        plist_path = app_dir / "Info.plist"
        with open(plist_path, "wb") as f:
            plistlib.dump({"CFBundleShortVersionString": version}, f)

    assert get_app_version(tmp_path / "TestApp.app") == expected


# ---------------------------------------------------------------------------
# lib/launchservices.py: deregister_stale_apps validation
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_empty_app_name(tmp_path):
    """Empty APP_NAME → ValueError."""
    with pytest.raises(ValueError, match="app_name"):
        deregister_stale_apps("", str(tmp_path))


def test_deregister_stale_apps_empty_derived_data(tmp_path):
    """Empty DERIVED_DATA → ValueError."""
    with pytest.raises(ValueError, match="derived_data"):
        deregister_stale_apps("TestApp", "")


def test_deregister_stale_apps_no_crash(tmp_path):
    """deregister_stale_apps should not crash with empty DerivedData."""
    deregister_stale_apps("TestApp", str(tmp_path))
