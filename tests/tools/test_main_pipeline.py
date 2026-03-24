# meta: updated=2026-03-15 08:26 checked=-
"""Tests for main() pipeline.

Split from: test_build_and_install_supplement2.py

Covers:
  Main-01: Full pipeline success
  Main-02: Test gate fails -> RuntimeError
  Main-03: Build fails -> RuntimeError
  Main-04: install_app fails (widget missing) -> RuntimeError
  Main-05: Deployment gate fails -> RuntimeError
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestMainPipeline:

    @patch("build_and_install.refresh_and_launch")
    @patch("build_and_install.check_data_integrity")
    @patch("build_and_install.verify_deployment")
    @patch("build_and_install.register_and_clean")
    @patch("build_and_install.verify_bundle_bits")
    @patch("build_and_install.verify_installed_widget")
    @patch("build_and_install.install_app")
    @patch("build_and_install.quit_running_app")
    @patch("build_and_install.build_app")
    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.run_test_gate")
    @patch("build_and_install.shelter_file")
    @patch("build_and_install.protect_files")
    @patch("build_and_install.backup_database")
    @patch("build_and_install.find_derived_data_dir")
    def test_main_success_path(
        self, mock_find_dd, mock_backup, mock_protect, mock_shelter,
        mock_test, mock_dereg, mock_build, mock_quit, mock_install,
        mock_verify_widget, mock_verify_bundle, mock_register,
        mock_verify_deploy, mock_check_integrity, mock_refresh,
        tmp_path,
    ):
        """Main-01: Full pipeline success."""
        mock_find_dd.return_value = None
        mock_backup.return_value = (5, tmp_path / "backup.db")
        mock_protect.return_value.__enter__ = MagicMock()
        mock_protect.return_value.__exit__ = MagicMock(return_value=False)
        mock_shelter.return_value.__enter__ = MagicMock()
        mock_shelter.return_value.__exit__ = MagicMock(return_value=False)
        build_path = tmp_path / "DerivedData/Build/Products/Debug/ClaudeUsageTracker.app"
        mock_build.return_value = build_path

        bai.main()

        mock_backup.assert_called_once()
        mock_test.assert_called_once()
        mock_build.assert_called_once()
        mock_quit.assert_called_once()
        mock_install.assert_called_once_with(build_path)
        mock_verify_widget.assert_called_once()
        mock_verify_bundle.assert_called_once()
        mock_register.assert_called_once()
        mock_verify_deploy.assert_called_once()
        mock_check_integrity.assert_called_once()
        mock_refresh.assert_called_once()

    @patch("build_and_install.shelter_file")
    @patch("build_and_install.protect_files")
    @patch("build_and_install.backup_database")
    @patch("build_and_install.find_derived_data_dir")
    @patch("build_and_install.run_test_gate")
    def test_main_test_failure(
        self, mock_test, mock_find_dd, mock_backup, mock_protect, mock_shelter,
    ):
        """Main-02: Test gate fails -> RuntimeError, no build/install."""
        mock_find_dd.return_value = None
        mock_backup.return_value = (0, None)
        mock_protect.return_value.__enter__ = MagicMock()
        mock_protect.return_value.__exit__ = MagicMock(return_value=False)
        mock_shelter.return_value.__enter__ = MagicMock()
        mock_shelter.return_value.__exit__ = MagicMock(return_value=False)
        mock_test.side_effect = RuntimeError("Unit tests failed")

        with pytest.raises(RuntimeError, match="Unit tests failed"):
            bai.main()

    @patch("build_and_install.shelter_file")
    @patch("build_and_install.protect_files")
    @patch("build_and_install.backup_database")
    @patch("build_and_install.find_derived_data_dir")
    @patch("build_and_install.run_test_gate")
    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.build_app")
    def test_main_build_failure(
        self, mock_build, mock_dereg, mock_test, mock_find_dd,
        mock_backup, mock_protect, mock_shelter,
    ):
        """Main-03: Build fails -> RuntimeError."""
        mock_find_dd.return_value = None
        mock_backup.return_value = (0, None)
        mock_protect.return_value.__enter__ = MagicMock()
        mock_protect.return_value.__exit__ = MagicMock(return_value=False)
        mock_shelter.return_value.__enter__ = MagicMock()
        mock_shelter.return_value.__exit__ = MagicMock(return_value=False)
        mock_build.side_effect = RuntimeError("Build failed.")

        with pytest.raises(RuntimeError, match="Build failed"):
            bai.main()

    @patch("build_and_install.refresh_and_launch")
    @patch("build_and_install.check_data_integrity")
    @patch("build_and_install.verify_deployment")
    @patch("build_and_install.register_and_clean")
    @patch("build_and_install.verify_bundle_bits")
    @patch("build_and_install.verify_installed_widget")
    @patch("build_and_install.install_app")
    @patch("build_and_install.quit_running_app")
    @patch("build_and_install.build_app")
    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.run_test_gate")
    @patch("build_and_install.shelter_file")
    @patch("build_and_install.protect_files")
    @patch("build_and_install.backup_database")
    @patch("build_and_install.find_derived_data_dir")
    def test_main_install_widget_missing(
        self, mock_find_dd, mock_backup, mock_protect, mock_shelter,
        mock_test, mock_dereg, mock_build, mock_quit, mock_install,
        mock_verify_widget, mock_verify_bundle, mock_register,
        mock_verify_deploy, mock_check_integrity, mock_refresh,
        tmp_path,
    ):
        """Main-04: install_app fails (widget missing) -> RuntimeError."""
        mock_find_dd.return_value = None
        mock_backup.return_value = (0, None)
        mock_protect.return_value.__enter__ = MagicMock()
        mock_protect.return_value.__exit__ = MagicMock(return_value=False)
        mock_shelter.return_value.__enter__ = MagicMock()
        mock_shelter.return_value.__exit__ = MagicMock(return_value=False)
        mock_build.return_value = tmp_path / "build.app"
        mock_install.side_effect = RuntimeError("Widget extension missing.")

        with pytest.raises(RuntimeError, match="Widget extension missing"):
            bai.main()

    @patch("build_and_install.refresh_and_launch")
    @patch("build_and_install.check_data_integrity")
    @patch("build_and_install.verify_deployment")
    @patch("build_and_install.register_and_clean")
    @patch("build_and_install.verify_bundle_bits")
    @patch("build_and_install.verify_installed_widget")
    @patch("build_and_install.install_app")
    @patch("build_and_install.quit_running_app")
    @patch("build_and_install.build_app")
    @patch("build_and_install.deregister_stale_apps")
    @patch("build_and_install.run_test_gate")
    @patch("build_and_install.shelter_file")
    @patch("build_and_install.protect_files")
    @patch("build_and_install.backup_database")
    @patch("build_and_install.find_derived_data_dir")
    def test_main_deployment_gate_fail(
        self, mock_find_dd, mock_backup, mock_protect, mock_shelter,
        mock_test, mock_dereg, mock_build, mock_quit, mock_install,
        mock_verify_widget, mock_verify_bundle, mock_register,
        mock_verify_deploy, mock_check_integrity, mock_refresh,
        tmp_path,
    ):
        """Main-05: Deployment gate fails -> RuntimeError."""
        mock_find_dd.return_value = None
        mock_backup.return_value = (0, None)
        mock_protect.return_value.__enter__ = MagicMock()
        mock_protect.return_value.__exit__ = MagicMock(return_value=False)
        mock_shelter.return_value.__enter__ = MagicMock()
        mock_shelter.return_value.__exit__ = MagicMock(return_value=False)
        mock_build.return_value = tmp_path / "build.app"
        mock_verify_deploy.side_effect = RuntimeError("GATE FAIL [1/3]")

        with pytest.raises(RuntimeError, match="GATE FAIL"):
            bai.main()
