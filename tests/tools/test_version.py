"""Tests for lib/version.py.

Covers:
  - get_app_version (using plistlib, no PlistBuddy dependency)
"""

import plistlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from version import get_app_version


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
