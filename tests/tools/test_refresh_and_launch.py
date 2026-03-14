"""Tests for refresh_and_launch().

Split from: test_build_and_install_supplement2.py

Covers:
  RL-01: killall Dock + sleep(2) + open app
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestRefreshAndLaunch:

    @patch("build_and_install.time.sleep")
    @patch("build_and_install.run")
    def test_dock_refresh_and_open(self, mock_run, mock_sleep, make_run_result):
        """RL-01: killall Dock + sleep(2) + open app."""
        mock_run.return_value = make_run_result()

        bai.refresh_and_launch("/Applications/ClaudeUsageTracker.app")

        assert mock_run.call_count == 2
        first_cmd = mock_run.call_args_list[0][0][0]
        assert first_cmd == ["killall", "Dock"]
        second_cmd = mock_run.call_args_list[1][0][0]
        assert second_cmd[0] == "open"

        mock_sleep.assert_called_once_with(2)
