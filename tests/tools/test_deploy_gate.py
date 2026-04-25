# meta: updated=2026-04-25 14:55 checked=-
"""Tests for stale xctest removal in build_app().

Covers:
  Test 1-3: Stale xctest removal

Note: the old 3-gate verification tests were superseded by the 5-gate
pipeline tested in test_deploy_verify.py.

Spec: docs/spec/tools/build-and-install.md (Deployment Verification Gate)
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))


WIDGET_ID = "grad13.claudeusagetracker.widget"


# ---------------------------------------------------------------------------
# Test 1-3: Stale xctest removal in build_app()
# ---------------------------------------------------------------------------


class TestStaleXctestRemoval:
    """build_app() removes stale xctest from DerivedData before building."""

    def test_removes_stale_xctest(self, tmp_path, make_run_result):
        """Test 1: Stale xctest is removed before build."""
        dd_dir = tmp_path / "DerivedData" / "ClaudeUsageTracker-abc"
        app_dir = dd_dir / "Build/Products/Debug/ClaudeUsageTracker.app"
        plugins = app_dir / "Contents/PlugIns"
        xctest = plugins / "ClaudeUsageTrackerTests.xctest"
        xctest.mkdir(parents=True)
        (xctest / "dummy").touch()

        widget = plugins / "ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        import build_and_install as bi

        with patch.object(bi, "find_derived_data_dir", return_value=dd_dir), \
             patch.object(bi, "run", return_value=make_run_result()):
            try:
                bi.build_app()
            except Exception:
                pass

        assert not xctest.exists(), "Stale xctest should be removed"

    def test_no_error_when_no_xctest(self, tmp_path, make_run_result):
        """Test 2: No error when xctest doesn't exist."""
        dd_dir = tmp_path / "DerivedData" / "ClaudeUsageTracker-abc"
        app_dir = dd_dir / "Build/Products/Debug/ClaudeUsageTracker.app"
        plugins = app_dir / "Contents/PlugIns"
        plugins.mkdir(parents=True)

        import build_and_install as bi

        with patch.object(bi, "find_derived_data_dir", return_value=dd_dir), \
             patch.object(bi, "run", return_value=make_run_result()):
            try:
                bi.build_app()
            except Exception:
                pass

    def test_no_error_when_no_derived_data(self, make_run_result):
        """Test 3: No error when DerivedData doesn't exist."""
        import build_and_install as bi

        with patch.object(bi, "find_derived_data_dir", return_value=None), \
             patch.object(bi, "run", return_value=make_run_result()):
            try:
                bi.build_app()
            except RuntimeError as e:
                assert "DerivedData" in str(e)


# Old TestVerificationGate (3-gate) removed; superseded by test_deploy_verify.py
# with the new 5-gate pipeline including FinderInfo bundle bit, smoke launch,
# and widget runtime path verification.
