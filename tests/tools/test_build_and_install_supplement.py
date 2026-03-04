"""Supplement tests for build_and_install.py.

Supplement for: tests/tools/test_build_and_install.py

Covers:
  Test 33: backup_database — creates backup file and returns row count
  Test 34: backup_database — DB not found returns (0, None)
  Test 35: backup_database — rotation keeps newest 10
"""

import sqlite3
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_usage_db_with_rows(db_path, row_count):
    """Create a usage.db with N rows."""
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
# Test 33: backup_database — creates backup and returns row count
# ---------------------------------------------------------------------------

def test_backup_database_creates_backup(tmp_path, monkeypatch):
    """backup_database creates a backup file and returns (row_count, backup_path)."""
    appgroup = tmp_path / "appgroup"
    appgroup.mkdir()
    db = appgroup / "usage.db"
    _create_usage_db_with_rows(db, 5)

    monkeypatch.setattr(bai, "APPGROUP_DIR", appgroup)
    monkeypatch.setattr(bai, "APPGROUP_DB", db)

    pre_count, backup_file = bai.backup_database()

    assert pre_count == 5
    assert backup_file is not None
    assert backup_file.exists()
    assert backup_file.parent == appgroup / "backups"
    assert backup_file.name.startswith("usage_")
    assert backup_file.name.endswith(".db")


# ---------------------------------------------------------------------------
# Test 34: backup_database — DB not found
# ---------------------------------------------------------------------------

def test_backup_database_db_not_found(tmp_path, monkeypatch):
    """backup_database returns (0, None) when usage.db doesn't exist."""
    appgroup = tmp_path / "appgroup"
    appgroup.mkdir()
    db = appgroup / "usage.db"  # does not exist

    monkeypatch.setattr(bai, "APPGROUP_DIR", appgroup)
    monkeypatch.setattr(bai, "APPGROUP_DB", db)

    pre_count, backup_file = bai.backup_database()

    assert pre_count == 0
    assert backup_file is None


# ---------------------------------------------------------------------------
# Test 35: backup_database — rotation keeps newest 10
# ---------------------------------------------------------------------------

def test_backup_database_rotation(tmp_path, monkeypatch):
    """backup_database rotates backups: keeps newest 10, deletes oldest."""
    import os
    import time

    appgroup = tmp_path / "appgroup"
    appgroup.mkdir()
    db = appgroup / "usage.db"
    _create_usage_db_with_rows(db, 1)

    # Pre-create 11 backup files
    backup_dir = appgroup / "backups"
    backup_dir.mkdir()
    for i in range(11):
        f = backup_dir / f"usage_20260301_{i:06d}.db"
        f.touch()
        mtime = time.time() - (12 - i) * 60
        os.utime(f, (mtime, mtime))

    monkeypatch.setattr(bai, "APPGROUP_DIR", appgroup)
    monkeypatch.setattr(bai, "APPGROUP_DB", db)

    bai.backup_database()

    # 11 pre-existing + 1 new = 12 total, rotation keeps 10
    remaining = list(backup_dir.glob("usage_*.db"))
    assert len(remaining) == 10
