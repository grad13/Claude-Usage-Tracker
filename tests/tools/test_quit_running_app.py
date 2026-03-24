# meta: updated=2026-03-15 08:26 checked=-
"""Tests for quit_running_app().

Split from: test_build_and_install_supplement2.py

Covers:
  QA-01: Sequence — osascript quit, sleep(2), killall, sleep(0.5)
"""

import sys
from pathlib import Path
from unittest.mock import call, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestQuitRunningApp:

    @patch("build_and_install.time.sleep")
    @patch("build_and_install.run")
    def test_quit_sequence(self, mock_run, mock_sleep, make_run_result):
        """QA-01: Sequence — osascript quit, sleep(2), killall, sleep(0.5)."""
        mock_run.return_value = make_run_result()

        bai.quit_running_app()

        assert mock_run.call_count == 2
        first_cmd = mock_run.call_args_list[0][0][0]
        assert "osascript" in first_cmd
        second_cmd = mock_run.call_args_list[1][0][0]
        assert "killall" in second_cmd

        assert mock_sleep.call_args_list == [call(2), call(0.5)]
