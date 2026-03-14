"""Supplement tests for check_data_integrity() edge cases.

Split from: test_build_and_install_supplement2.py

Covers:
  CI-01: backup_file=None -> skip (no exception)
  CI-04: sqlite3.Error during check -> RuntimeError (lost=-1)
"""

import sqlite3
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestCheckDataIntegrityEdgeCases:

    def test_backup_file_none_skips(self, monkeypatch):
        """CI-01: backup_file=None -> skip (no exception, no check)."""
        bai.check_data_integrity(None)

    @patch("build_and_install.check_lost_rows")
    def test_sqlite3_error_warns(self, mock_check, tmp_path, monkeypatch):
        """CI-04: sqlite3.Error during check -> WARNING only (non-fatal)."""
        backup = tmp_path / "backup.db"
        backup.touch()
        db = tmp_path / "usage.db"
        db.touch()
        monkeypatch.setattr(bai, "APPGROUP_DB", db)

        mock_check.side_effect = sqlite3.Error("database is locked")

        with pytest.raises(RuntimeError, match="rows lost during deploy"):
            bai.check_data_integrity(backup)
