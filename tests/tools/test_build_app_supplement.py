# meta: updated=2026-03-15 08:26 checked=-
"""Supplement tests for build_app().

Split from: test_build_and_install_supplement2.py

Covers:
  BA-01: Build success + artifact exists -> returns Path
  BA-02: Build failure (rc!=0) -> RuntimeError
  BA-03: Build success + DerivedData not found -> RuntimeError
  BA-04: Build success + artifact missing -> RuntimeError
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestBuildApp:

    @patch("build_and_install.run")
    @patch("build_and_install.find_derived_data_dir")
    def test_build_success_returns_path(self, mock_find_dd, mock_run, tmp_path, make_run_result):
        """BA-01: Build success + artifact exists -> returns Path."""
        dd_dir = tmp_path / "DerivedData" / "ClaudeUsageTracker-xxx"
        app_dir = dd_dir / "Build/Products/Debug/ClaudeUsageTracker.app"
        app_dir.mkdir(parents=True)

        mock_find_dd.return_value = dd_dir
        mock_run.return_value = make_run_result(returncode=0, stdout="BUILD SUCCEEDED\n")

        result = bai.build_app()
        assert result == app_dir

    @patch("build_and_install.run")
    @patch("build_and_install.find_derived_data_dir")
    def test_build_failure_raises(self, mock_find_dd, mock_run, make_run_result):
        """BA-02: Build failure (rc!=0) -> RuntimeError."""
        mock_find_dd.return_value = None
        mock_run.return_value = make_run_result(returncode=65, stdout="BUILD FAILED\n")

        with pytest.raises(RuntimeError, match="Build failed"):
            bai.build_app()

    @patch("build_and_install.run")
    @patch("build_and_install.find_derived_data_dir")
    def test_build_success_dd_not_found_raises(self, mock_find_dd, mock_run, make_run_result):
        """BA-03: Build success + DerivedData not found after build -> RuntimeError."""
        mock_find_dd.return_value = None
        mock_run.return_value = make_run_result(returncode=0, stdout="BUILD SUCCEEDED\n")

        with pytest.raises(RuntimeError, match="DerivedData not found after build"):
            bai.build_app()

    @patch("build_and_install.run")
    @patch("build_and_install.find_derived_data_dir")
    def test_build_success_artifact_missing_raises(self, mock_find_dd, mock_run, tmp_path, make_run_result):
        """BA-04: Build success + artifact missing in DerivedData -> RuntimeError."""
        dd_dir = tmp_path / "DerivedData" / "ClaudeUsageTracker-xxx"
        dd_dir.mkdir(parents=True)

        mock_find_dd.return_value = dd_dir
        mock_run.return_value = make_run_result(returncode=0, stdout="BUILD SUCCEEDED\n")

        with pytest.raises(RuntimeError, match="Built app not found"):
            bai.build_app()
