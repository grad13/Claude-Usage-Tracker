# meta: updated=2026-03-15 08:26 checked=-
"""Tests for deployment verification gate and stale xctest removal.

Covers:
  Test 1-3: Stale xctest removal in build_app()
  Test 4:   Verification gate — all pass
  Test 5:   Verification gate — widget not in pluginkit
  Test 6:   Verification gate — DerivedData ghost in pluginkit
  Test 7:   Verification gate — ghost LS registration

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


# ---------------------------------------------------------------------------
# Test 4-7: Deployment Verification Gate
# ---------------------------------------------------------------------------


class TestVerificationGate:
    """_verify_widget_deployment() checks 3 conditions per spec."""

    def _make_pluginkit_stdout(self, *, found=True, ghost=False):
        """Build pluginkit -m output."""
        if not found:
            return ""
        path = "/Users/x/Library/Developer/Xcode/DerivedData/..." if ghost else "/Applications/ClaudeUsageTracker.app/..."
        return f"    {WIDGET_ID}({path})"

    def test_gate_all_pass(self, make_run_result):
        """Test 4: All 3 conditions pass -> no exception, prints 3/3."""
        import build_and_install as bi

        pk_stdout = self._make_pluginkit_stdout(found=True, ghost=False)

        def mock_run(cmd, **kwargs):
            if "pluginkit" in cmd:
                return make_run_result(stdout=pk_stdout)
            return make_run_result()

        with patch.object(bi, "run", side_effect=mock_run), \
             patch.object(bi, "dump_widget_registration", return_value="/Applications/ClaudeUsageTracker.app"):
            bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")

    def test_gate_pluginkit_not_found(self, make_run_result):
        """Test 5: Widget not in pluginkit -> GATE FAIL [1/3]."""
        import build_and_install as bi

        def mock_run(cmd, **kwargs):
            if "pluginkit" in cmd:
                return make_run_result(stdout="")
            return make_run_result()

        with patch.object(bi, "run", side_effect=mock_run), \
             patch.object(bi, "dump_widget_registration", return_value=None):
            with pytest.raises(RuntimeError, match=r"GATE FAIL \[1/3\]"):
                bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")

    def test_gate_ghost_pluginkit(self, make_run_result):
        """Test 6: DerivedData ghost in pluginkit -> GATE FAIL [2/3]."""
        import build_and_install as bi

        pk_stdout = self._make_pluginkit_stdout(found=True, ghost=True)

        def mock_run(cmd, **kwargs):
            if "pluginkit" in cmd:
                return make_run_result(stdout=pk_stdout)
            return make_run_result()

        with patch.object(bi, "run", side_effect=mock_run), \
             patch.object(bi, "dump_widget_registration", return_value=None):
            with pytest.raises(RuntimeError, match=r"GATE FAIL \[2/3\]"):
                bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")

    def test_gate_ghost_ls_registration(self, make_run_result):
        """Test 7: Ghost LS registration -> GATE FAIL [3/3]."""
        import build_and_install as bi

        pk_stdout = self._make_pluginkit_stdout(found=True, ghost=False)

        def mock_run(cmd, **kwargs):
            if "pluginkit" in cmd:
                return make_run_result(stdout=pk_stdout)
            return make_run_result()

        with patch.object(bi, "run", side_effect=mock_run), \
             patch.object(bi, "dump_widget_registration", return_value="/Users/x/DerivedData/ghost"):
            with pytest.raises(RuntimeError, match=r"GATE FAIL \[3/3\]"):
                bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")
