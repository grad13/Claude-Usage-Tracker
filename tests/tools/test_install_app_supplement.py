"""Supplement tests for install_app().

Split from: test_build_and_install_supplement2.py

Covers:
  IA-02: No existing app -> skip backup, rename .new to .app
  IA-04: Leftover .new cleanup before install
"""

import shutil
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestInstallApp:

    @patch("build_and_install.run")
    def test_no_existing_app_swap_only(self, mock_run, tmp_path, monkeypatch, make_run_result):
        """IA-02: No existing app -> skip backup, rename .new to .app."""
        install_dir = tmp_path / "Applications"
        install_dir.mkdir()
        monkeypatch.setattr(bai, "INSTALL_DIR", install_dir)

        build_app_path = tmp_path / "build" / "ClaudeUsageTracker.app"
        widget = build_app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        def run_side_effect(cmd, **kwargs):
            if cmd[0] == "cp" and "-R" in cmd:
                shutil.copytree(str(cmd[2]), str(cmd[3]))
            return make_run_result()

        mock_run.side_effect = run_side_effect

        bai.install_app(build_app_path)

        installed = install_dir / "ClaudeUsageTracker.app"
        assert installed.exists()

    @patch("build_and_install.run")
    def test_leftover_new_cleaned_before_install(self, mock_run, tmp_path, monkeypatch, make_run_result):
        """IA-04: Leftover .app.new from previous failed install -> rmtree before copy."""
        install_dir = tmp_path / "Applications"
        install_dir.mkdir()
        monkeypatch.setattr(bai, "INSTALL_DIR", install_dir)

        leftover = install_dir / "ClaudeUsageTracker.app.new"
        leftover.mkdir(parents=True)
        (leftover / "stale_file").touch()
        assert leftover.exists()

        build_app_path = tmp_path / "build" / "ClaudeUsageTracker.app"
        widget = build_app_path / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
        widget.mkdir(parents=True)

        def run_side_effect(cmd, **kwargs):
            if cmd[0] == "cp" and "-R" in cmd:
                shutil.copytree(str(cmd[2]), str(cmd[3]))
            return make_run_result()

        mock_run.side_effect = run_side_effect

        bai.install_app(build_app_path)

        installed = install_dir / "ClaudeUsageTracker.app"
        assert installed.exists()
        assert not (install_dir / "ClaudeUsageTracker.app.new").exists()
