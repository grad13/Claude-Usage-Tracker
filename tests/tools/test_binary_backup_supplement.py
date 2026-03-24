# meta: updated=2026-03-15 08:26 checked=-
# Supplement for: tests/tools/test_binary_backup.py
"""Supplement tests for db_backup.py — cases missing from existing tests.

Covers:
  RO-02: rotate_backups — below threshold (5 files, keep=10) -> no deletion
  RO-04: rotate_backups — keep=0 -> all files deleted
  BD-03: backup_database — corrupted DB (sqlite3.Error) -> sentinel -1 + backup
  BD-04: backup_database — missing usage_log table -> sentinel -1 + backup
  CL-03: check_lost_rows — current DB empty -> all backup rows reported lost
  CL-04: check_lost_rows — invalid backup DB -> raises sqlite3.Error
"""

import os
import sqlite3
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from db_backup import backup_database, check_lost_rows, rotate_backups


class TestRotateBackups:

    def test_below_threshold(self, tmp_path):
        """RO-02: When backup count (5) < keep (10), no files are deleted."""
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()

        files = []
        for i in range(5):
            f = backup_dir / f"usage_20260301_{i:06d}.db"
            f.touch()
            mtime = time.time() - (5 - i) * 60
            os.utime(f, (mtime, mtime))
            files.append(f)

        rotate_backups(backup_dir, keep=10)

        remaining = list(backup_dir.glob("usage_*.db"))
        assert len(remaining) == 5
        for f in files:
            assert f.exists()

    def test_keep_zero(self, tmp_path):
        """RO-04: keep=0 deletes all backup files."""
        backup_dir = tmp_path / "backups"
        backup_dir.mkdir()

        for i in range(5):
            f = backup_dir / f"usage_20260301_{i:06d}.db"
            f.touch()
            mtime = time.time() - (5 - i) * 60
            os.utime(f, (mtime, mtime))

        rotate_backups(backup_dir, keep=0)

        remaining = list(backup_dir.glob("usage_*.db"))
        assert len(remaining) == 0


class TestBackupDatabase:

    def test_corrupted_db(self, tmp_path, capsys):
        """BD-03: Corrupted DB causes sqlite3.Error -> pre_count=-1, backup still created."""
        appgroup = tmp_path / "appgroup"
        appgroup.mkdir()
        db = appgroup / "usage.db"

        db.write_bytes(b"this is not a valid sqlite database" * 10)

        pre_count, backup_file = backup_database(db, appgroup)

        assert pre_count == -1
        assert backup_file is not None
        assert backup_file.exists()
        assert backup_file.parent == appgroup / "backups"

        captured = capsys.readouterr()
        assert "WARNING" in captured.out

    def test_missing_table(self, tmp_path, capsys):
        """BD-04: DB exists but has no usage_log table -> OperationalError -> pre_count=-1."""
        appgroup = tmp_path / "appgroup"
        appgroup.mkdir()
        db = appgroup / "usage.db"

        conn = sqlite3.connect(str(db))
        conn.execute("CREATE TABLE other_table (id INTEGER PRIMARY KEY)")
        conn.commit()
        conn.close()

        pre_count, backup_file = backup_database(db, appgroup)

        assert pre_count == -1
        assert backup_file is not None
        assert backup_file.exists()

        captured = capsys.readouterr()
        assert "WARNING" in captured.out
        assert "OperationalError" in captured.out


class TestCheckLostRows:

    def test_current_empty(self, tmp_path, usage_db_with_rows):
        """CL-03: Current DB is empty -> all backup rows reported as lost."""
        current_db = usage_db_with_rows(0)
        backup_db = tmp_path / "backup" / "backup.db"
        backup_db.parent.mkdir()

        # Create backup with 5 rows using same schema
        conn = sqlite3.connect(str(backup_db))
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS hourly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS weekly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                hourly_percent REAL,
                weekly_percent REAL,
                hourly_session_id INTEGER REFERENCES hourly_sessions(id),
                weekly_session_id INTEGER REFERENCES weekly_sessions(id),
                CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL)
            );
            """
        )
        for i in range(5):
            conn.execute(
                "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (?, ?)",
                (1000 + i, 50.0),
            )
        conn.commit()
        conn.close()

        lost = check_lost_rows(str(current_db), str(backup_db))

        assert lost == 5

    def test_invalid_backup(self, tmp_path, usage_db_with_rows):
        """CL-04: Invalid backup DB causes ATTACH to fail -> raises sqlite3.Error."""
        current_db = usage_db_with_rows(3)
        backup_db = tmp_path / "backup" / "backup.db"
        backup_db.parent.mkdir()

        backup_db.write_bytes(b"not a sqlite database" * 10)

        with pytest.raises(sqlite3.Error):
            check_lost_rows(str(current_db), str(backup_db))
