# meta: updated=2026-03-15 08:26 checked=-
"""Supplement tests for run_test_gate().

Split from: test_build_and_install_supplement2.py

Covers:
  TG-01: Test success (rc=0) -> no exception
  TG-02: Test failure (rc!=0) -> RuntimeError
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestRunTestGate:

    @patch("build_and_install.run")
    def test_success_prints_last_5_lines(self, mock_run, make_run_result):
        """TG-01: Test success (rc=0) -> no exception, prints last 5 lines."""
        lines = "\n".join([f"line{i}" for i in range(10)])
        mock_run.return_value = make_run_result(returncode=0, stdout=lines)

        bai.run_test_gate()

        mock_run.assert_called_once()
        cmd = mock_run.call_args[0][0]
        assert "xcodebuild" in cmd
        assert "test" in cmd

    @patch("build_and_install.run")
    def test_failure_raises_runtimeerror(self, mock_run, make_run_result):
        """TG-02: Test failure (rc!=0) -> RuntimeError."""
        mock_run.return_value = make_run_result(returncode=65, stdout="TEST FAILED\n")

        with pytest.raises(RuntimeError, match="Unit tests failed"):
            bai.run_test_gate()
