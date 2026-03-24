# meta: updated=2026-03-15 08:26 checked=-
"""Supplement tests for register_and_clean().

Split from: test_build_and_install_supplement2.py

Covers:
  RC-01: Entitlements present -> deregister + register + process kills
  RC-02: App missing application-groups -> RuntimeError
  RC-03: Widget missing application-groups -> RuntimeError
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestRegisterAndClean:

    @patch("build_and_install.time.sleep")
    @patch("build_and_install.register_app")
    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.run")
    def test_entitlements_ok(self, mock_run, mock_dereg, mock_reg, mock_sleep, tmp_path, make_run_result):
        """RC-01: Entitlements present -> deregister + register + process kills."""
        app_path = tmp_path / "ClaudeUsageTracker.app"
        widget = app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        def run_side_effect(cmd, **kwargs):
            r = make_run_result()
            if cmd[0] == "codesign":
                r.stdout = "application-groups\ncom.apple.security.app-sandbox"
            return r

        mock_run.side_effect = run_side_effect

        bai.register_and_clean(str(app_path))

        mock_dereg.assert_called_once()
        mock_reg.assert_called_once_with(str(app_path))
        killall_calls = [c for c in mock_run.call_args_list if c[0][0][0] == "killall"]
        assert len(killall_calls) == 3

    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.run")
    def test_app_missing_app_groups(self, mock_run, mock_dereg, tmp_path, make_run_result):
        """RC-02: App missing application-groups entitlement -> RuntimeError."""
        app_path = tmp_path / "ClaudeUsageTracker.app"
        widget = app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        def run_side_effect(cmd, **kwargs):
            r = make_run_result()
            if cmd[0] == "codesign":
                target = cmd[-1]
                if "appex" not in target:
                    r.stdout = "com.apple.security.app-sandbox"
                else:
                    r.stdout = "application-groups"
            return r

        mock_run.side_effect = run_side_effect

        with pytest.raises(RuntimeError, match="Entitlements missing"):
            bai.register_and_clean(str(app_path))

    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.run")
    def test_widget_missing_app_groups(self, mock_run, mock_dereg, tmp_path, make_run_result):
        """RC-03: Widget missing application-groups entitlement -> RuntimeError."""
        app_path = tmp_path / "ClaudeUsageTracker.app"
        widget = app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        def run_side_effect(cmd, **kwargs):
            r = make_run_result()
            if cmd[0] == "codesign":
                target = cmd[-1]
                if "appex" in target:
                    r.stdout = "com.apple.security.app-sandbox"
                else:
                    r.stdout = "application-groups"
            return r

        mock_run.side_effect = run_side_effect

        with pytest.raises(RuntimeError, match="Entitlements missing"):
            bai.register_and_clean(str(app_path))
