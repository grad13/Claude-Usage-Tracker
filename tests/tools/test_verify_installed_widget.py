# meta: updated=2026-03-15 08:26 checked=-
"""Tests for verify_installed_widget().

Split from: test_build_and_install_supplement2.py

Covers:
  VW-01: Size match + mtime OK -> SetFile called
  VW-02: Size mismatch -> RuntimeError
  VW-03: Installed mtime older than source -> RuntimeError
  VW-04: Widget binary missing -> skip comparison, SetFile only
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestVerifyInstalledWidget:

    @patch("build_and_install.run")
    def test_size_and_mtime_match(self, mock_run, tmp_path, make_run_result, make_widget_binary):
        """VW-01: Size match + mtime OK -> SetFile called, no exception."""
        build_app = tmp_path / "build" / "App.app"
        installed_app = tmp_path / "installed" / "App.app"

        make_widget_binary(build_app, size=2048, mtime_offset=-10)
        make_widget_binary(installed_app, size=2048, mtime_offset=0)

        mock_run.return_value = make_run_result()

        bai.verify_installed_widget(build_app, installed_app)

        cmd = mock_run.call_args[0][0]
        assert cmd[0] == "SetFile"

    @patch("build_and_install.run")
    def test_size_mismatch_raises(self, mock_run, tmp_path, make_widget_binary):
        """VW-02: Size mismatch -> RuntimeError."""
        build_app = tmp_path / "build" / "App.app"
        installed_app = tmp_path / "installed" / "App.app"

        make_widget_binary(build_app, size=2048)
        make_widget_binary(installed_app, size=1024)

        with pytest.raises(RuntimeError, match="size mismatch"):
            bai.verify_installed_widget(build_app, installed_app)

    @patch("build_and_install.run")
    def test_mtime_stale_raises(self, mock_run, tmp_path, make_widget_binary):
        """VW-03: Installed mtime older than source -> RuntimeError."""
        build_app = tmp_path / "build" / "App.app"
        installed_app = tmp_path / "installed" / "App.app"

        make_widget_binary(build_app, size=512, mtime_offset=10)
        make_widget_binary(installed_app, size=512, mtime_offset=-10)

        with pytest.raises(RuntimeError, match="stale"):
            bai.verify_installed_widget(build_app, installed_app)

    @patch("build_and_install.run")
    def test_widget_binary_missing_setfile_only(self, mock_run, tmp_path, make_run_result):
        """VW-04: Widget binary does not exist -> skip comparison, SetFile only."""
        build_app = tmp_path / "build" / "App.app"
        build_app.mkdir(parents=True)
        installed_app = tmp_path / "installed" / "App.app"
        installed_app.mkdir(parents=True)

        mock_run.return_value = make_run_result()

        bai.verify_installed_widget(build_app, installed_app)

        cmd = mock_run.call_args[0][0]
        assert cmd[0] == "SetFile"
