# meta: updated=2026-03-15 08:26 checked=-
"""Regression test for FinderInfo self-repair.

Split from: test_build_and_install_supplement2.py

Covers:
  VB-03: repair deletes only FinderInfo and never invokes SetFile
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestVerifyBundleBitsEdge:

    @patch("build_and_install.run")
    def test_repair_deletes_only_finderinfo(self, mock_run, tmp_path, make_run_result):
        """VB-03: strict-signature repair never recreates FinderInfo."""
        app_path = str(tmp_path / "ClaudeUsageTracker.app")
        mock_run.return_value = make_run_result(returncode=0)

        bai._repair_finderinfo(app_path)

        mock_run.assert_called_once_with(
            ["xattr", "-d", "com.apple.FinderInfo", app_path],
            on_error="warn",
            label="xattr -d FinderInfo",
        )
