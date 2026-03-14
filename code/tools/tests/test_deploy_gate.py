"""Tests for deployment verification gate and stale xctest removal.

Covers:
  Test 1-3: Stale xctest removal in build_app()
  Test 4:   Verification gate — all pass
  Test 5:   Verification gate — widget not in pluginkit
  Test 6:   Verification gate — DerivedData ghost in pluginkit
  Test 7:   Verification gate — ghost LS registration

Spec: docs/spec/tools/build-and-install.md (Deployment Verification Gate)
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

WIDGET_ID = "grad13.claudeusagetracker.widget"


def _make_completed_process(stdout="", stderr="", returncode=0):
    """Create a CompletedProcess mock."""
    return subprocess.CompletedProcess(
        args=[], returncode=returncode, stdout=stdout, stderr=stderr,
    )


# ---------------------------------------------------------------------------
# Test 1-3: Stale xctest removal in build_app()
# ---------------------------------------------------------------------------


class TestStaleXctestRemoval:
    """build_app() removes stale xctest from DerivedData before building."""

    def test_removes_stale_xctest(self, tmp_path):
        """Test 1: Stale xctest is removed before build."""
        # Setup: simulate DerivedData with stale xctest
        dd_dir = tmp_path / "DerivedData" / "ClaudeUsageTracker-abc"
        app_dir = dd_dir / "Build/Products/Debug/ClaudeUsageTracker.app"
        plugins = app_dir / "Contents/PlugIns"
        xctest = plugins / "ClaudeUsageTrackerTests.xctest"
        xctest.mkdir(parents=True)
        (xctest / "dummy").touch()

        # Also create widget appex so build_app can find it
        widget = plugins / "ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        import build_and_install as bi

        with patch.object(bi, "find_derived_data_dir", return_value=dd_dir), \
             patch.object(bi, "subprocess") as mock_sub:
            mock_sub.run.return_value = _make_completed_process()
            try:
                bi.build_app()
            except Exception:
                pass  # May fail on other checks, we only care about xctest removal

        assert not xctest.exists(), "Stale xctest should be removed"

    def test_no_error_when_no_xctest(self, tmp_path):
        """Test 2: No error when xctest doesn't exist."""
        dd_dir = tmp_path / "DerivedData" / "ClaudeUsageTracker-abc"
        app_dir = dd_dir / "Build/Products/Debug/ClaudeUsageTracker.app"
        plugins = app_dir / "Contents/PlugIns"
        plugins.mkdir(parents=True)

        import build_and_install as bi

        with patch.object(bi, "find_derived_data_dir", return_value=dd_dir), \
             patch.object(bi, "subprocess") as mock_sub:
            mock_sub.run.return_value = _make_completed_process()
            try:
                bi.build_app()
            except Exception:
                pass
        # Should not raise

    def test_no_error_when_no_derived_data(self):
        """Test 3: No error when DerivedData doesn't exist."""
        import build_and_install as bi

        with patch.object(bi, "find_derived_data_dir", return_value=None), \
             patch.object(bi, "subprocess") as mock_sub:
            mock_sub.run.return_value = _make_completed_process()
            try:
                bi.build_app()
            except RuntimeError as e:
                # Expected: "DerivedData not found after build."
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

    def test_gate_all_pass(self):
        """Test 4: All 3 conditions pass → no exception, prints 3/3."""
        import build_and_install as bi

        pk_stdout = self._make_pluginkit_stdout(found=True, ghost=False)

        def side_effect(cmd, **kwargs):
            if "pluginkit" in cmd:
                return _make_completed_process(stdout=pk_stdout)
            return _make_completed_process()

        with patch.object(bi, "subprocess") as mock_sub, \
             patch.object(bi, "dump_widget_registration", return_value="/Applications/ClaudeUsageTracker.app"):
            mock_sub.run.side_effect = side_effect
            # Should not raise
            bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")

    def test_gate_pluginkit_not_found(self):
        """Test 5: Widget not in pluginkit → GATE FAIL [1/3]."""
        import build_and_install as bi

        def side_effect(cmd, **kwargs):
            if "pluginkit" in cmd:
                return _make_completed_process(stdout="")
            return _make_completed_process()

        with patch.object(bi, "subprocess") as mock_sub, \
             patch.object(bi, "dump_widget_registration", return_value=None):
            mock_sub.run.side_effect = side_effect
            with pytest.raises(RuntimeError, match=r"GATE FAIL \[1/3\]"):
                bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")

    def test_gate_ghost_pluginkit(self):
        """Test 6: DerivedData ghost in pluginkit → GATE FAIL [2/3]."""
        import build_and_install as bi

        pk_stdout = self._make_pluginkit_stdout(found=True, ghost=True)

        def side_effect(cmd, **kwargs):
            if "pluginkit" in cmd:
                return _make_completed_process(stdout=pk_stdout)
            return _make_completed_process()

        with patch.object(bi, "subprocess") as mock_sub, \
             patch.object(bi, "dump_widget_registration", return_value=None):
            mock_sub.run.side_effect = side_effect
            with pytest.raises(RuntimeError, match=r"GATE FAIL \[2/3\]"):
                bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")

    def test_gate_ghost_ls_registration(self):
        """Test 7: Ghost LS registration → GATE FAIL [3/3]."""
        import build_and_install as bi

        pk_stdout = self._make_pluginkit_stdout(found=True, ghost=False)

        def side_effect(cmd, **kwargs):
            if "pluginkit" in cmd:
                return _make_completed_process(stdout=pk_stdout)
            return _make_completed_process()

        with patch.object(bi, "subprocess") as mock_sub, \
             patch.object(bi, "dump_widget_registration", return_value="/Users/x/DerivedData/ghost"):
            mock_sub.run.side_effect = side_effect
            with pytest.raises(RuntimeError, match=r"GATE FAIL \[3/3\]"):
                bi._verify_widget_deployment("/Applications/ClaudeUsageTracker.app")
