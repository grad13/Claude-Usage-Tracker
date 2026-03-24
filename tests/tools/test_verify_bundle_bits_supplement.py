# meta: updated=2026-03-15 08:26 checked=-
"""Supplement tests for verify_bundle_bits() edge cases.

Split from: test_build_and_install_supplement2.py

Covers:
  VB-03: GetFileInfo failure (on_error='warn') -> no exception raised
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestVerifyBundleBitsEdge:

    @patch("build_and_install.run")
    def test_getfileinfo_failure_skips(self, mock_run, tmp_path, make_run_result):
        """VB-03: GetFileInfo failure (on_error='warn') -> no exception raised."""
        app_path = str(tmp_path / "ClaudeUsageTracker.app")
        mock_run.return_value = make_run_result(returncode=1, stdout="", stderr="not found")

        bai.verify_bundle_bits(app_path)
