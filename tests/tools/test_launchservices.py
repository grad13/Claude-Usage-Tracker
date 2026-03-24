# meta: updated=2026-03-04 18:05 checked=-
"""Tests for lib/launchservices.py.

Covers:
  - deregister_stale_apps input validation
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from launchservices import deregister_stale_apps


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
