# Supplement for: tests/tools/test_binary_backup.py
"""Supplement tests for db_backup.py — cases missing from existing tests.

Covers:
  RO-02: rotate_backups — below threshold (5 files, keep=10) → no deletion
  RO-04: rotate_backups — keep=0 → all files deleted
  BD-03: backup_database — corrupted DB (sqlite3.Error) → sentinel -1 + backup
  BD-04: backup_database — missing usage_log table → sentinel -1 + backup
  CL-03: check_lost_rows — current DB empty → all backup rows reported lost
  CL-04: check_lost_rows — invalid backup DB → raises sqlite3.Error
"""

import os
import sqlite3
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from db_backup import backup_database, check_lost_rows, rotate_backups


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_usage_db_with_rows(db_path, row_count):
    """Create a usage.db with the standard schema and N rows."""
    conn = sqlite3.connect(str(db_path))
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
    for i in range(row_count):
        conn.execute(
            "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (?, ?)",
            (1000 + i, 50.0),
        )
    conn.commit()
    conn.close()


# ---------------------------------------------------------------------------
# RO-02: rotate_backups — below threshold (5 files, keep=10)
# ---------------------------------------------------------------------------

def test_rotate_backups_below_threshold(tmp_path):
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


# ---------------------------------------------------------------------------
# RO-04: rotate_backups — keep=0 → all files deleted
# ---------------------------------------------------------------------------

def test_rotate_backups_keep_zero(tmp_path):
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


# ---------------------------------------------------------------------------
# BD-03: backup_database — corrupted DB → sentinel -1 + backup created
# ---------------------------------------------------------------------------

def test_backup_database_corrupted_db(tmp_path, capsys):
    """BD-03: Corrupted DB causes sqlite3.Error → pre_count=-1, backup still created."""
    appgroup = tmp_path / "appgroup"
    appgroup.mkdir()
    db = appgroup / "usage.db"

    # Write garbage to create a corrupted DB file
    db.write_bytes(b"this is not a valid sqlite database" * 10)

    pre_count, backup_file = backup_database(db, appgroup)

    assert pre_count == -1
    assert backup_file is not None
    assert backup_file.exists()
    assert backup_file.parent == appgroup / "backups"

    captured = capsys.readouterr()
    assert "WARNING" in captured.out


# ---------------------------------------------------------------------------
# BD-04: backup_database — missing usage_log table → sentinel -1 + backup
# ---------------------------------------------------------------------------

def test_backup_database_missing_table(tmp_path, capsys):
    """BD-04: DB exists but has no usage_log table → OperationalError → pre_count=-1."""
    appgroup = tmp_path / "appgroup"
    appgroup.mkdir()
    db = appgroup / "usage.db"

    # Create a valid SQLite DB without the usage_log table
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


# ---------------------------------------------------------------------------
# CL-03: check_lost_rows — current DB empty → all backup rows lost
# ---------------------------------------------------------------------------

def test_check_lost_rows_current_empty(tmp_path):
    """CL-03: Current DB is empty → all backup rows reported as lost."""
    current_db = tmp_path / "current.db"
    backup_db = tmp_path / "backup.db"

    # Current DB: schema only, no rows
    _create_usage_db_with_rows(current_db, 0)

    # Backup DB: 5 rows
    _create_usage_db_with_rows(backup_db, 5)

    lost = check_lost_rows(str(current_db), str(backup_db))

    assert lost == 5


# ---------------------------------------------------------------------------
# CL-04: check_lost_rows — invalid backup DB → raises sqlite3.Error
# ---------------------------------------------------------------------------

def test_check_lost_rows_invalid_backup(tmp_path):
    """CL-04: Invalid backup DB causes ATTACH to fail → raises sqlite3.Error."""
    current_db = tmp_path / "current.db"
    backup_db = tmp_path / "backup.db"

    _create_usage_db_with_rows(current_db, 3)

    # Write garbage as backup DB
    backup_db.write_bytes(b"not a sqlite database" * 10)

    with pytest.raises(sqlite3.Error):
        check_lost_rows(str(current_db), str(backup_db))
