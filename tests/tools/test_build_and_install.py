"""Tests for build_and_install.py logic.

Covers:
  Test 1-4: Lost row detection SQL (backup_database equivalent)
  Test 5:   DB backup rotation (keep newest 10)
"""

import os
import sqlite3
import time
from pathlib import Path

import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_usage_db(path):
    """Create a usage.db with the production schema."""
    conn = sqlite3.connect(str(path))
    conn.executescript(
        """
        CREATE TABLE hourly_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resets_at INTEGER NOT NULL UNIQUE
        );
        CREATE TABLE weekly_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resets_at INTEGER NOT NULL UNIQUE
        );
        CREATE TABLE usage_log (
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
    conn.close()


def _insert_rows(db_path, percentages):
    """Insert rows into usage_log with sequential timestamps."""
    conn = sqlite3.connect(str(db_path))
    for i, pct in enumerate(percentages, start=1):
        conn.execute(
            "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (?, ?)",
            (1000 + i, pct),
        )
    conn.commit()
    conn.close()


def _run_lost_check(current_db, backup_db):
    """Run the same lost-row detection SQL as build_and_install.py."""
    conn = sqlite3.connect(str(current_db))
    conn.execute(f"ATTACH '{backup_db}' AS backup")
    lost = conn.execute(
        "SELECT COUNT(*) FROM backup.usage_log "
        "WHERE rowid NOT IN (SELECT rowid FROM main.usage_log)"
    ).fetchone()[0]
    conn.close()
    return lost


# ---------------------------------------------------------------------------
# Test 1-4: Lost row detection SQL
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "backup_rows,current_rows,expected_lost",
    [
        ([10.0, 20.0, 30.0], [10.0], 2),              # Test 1: 2 rows lost
        ([50.0, 50.0, 50.0], [50.0, 50.0, 50.0], 0),  # Test 2: no loss
        ([10.0, 20.0], [10.0, 20.0, 30.0], 0),         # Test 3: extra rows ignored
        ([], [50.0, 60.0, 70.0], 0),                    # Test 4: empty backup
    ],
    ids=["rows_lost", "no_loss", "extra_rows", "empty_backup"],
)
def test_lost_row_detection(tmp_path, backup_rows, current_rows, expected_lost):
    backup_db = tmp_path / "backup.db"
    current_db = tmp_path / "current.db"

    _create_usage_db(backup_db)
    _create_usage_db(current_db)
    _insert_rows(backup_db, backup_rows)
    _insert_rows(current_db, current_rows)

    assert _run_lost_check(current_db, backup_db) == expected_lost


# ---------------------------------------------------------------------------
# Test 5: DB backup rotation (keep newest 10)
# ---------------------------------------------------------------------------

def test_backup_rotation(tmp_path):
    """12 backup files → rotation keeps 10, deletes oldest 2."""
    backup_dir = tmp_path / "backups"
    backup_dir.mkdir()

    # Create 12 files with distinct mtimes (oldest first)
    for i in range(1, 13):
        fname = f"usage_20260227_{i:02d}0000.db"
        f = backup_dir / fname
        f.touch()
        mtime = time.time() - (13 - i) * 60
        os.utime(f, (mtime, mtime))

    # Same rotation logic as build_and_install.py
    backups = sorted(backup_dir.glob("usage_*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in backups[10:]:
        old.unlink()

    remaining = sorted(backup_dir.glob("usage_*.db"))
    assert len(remaining) == 10
    assert not (backup_dir / "usage_20260227_010000.db").exists()
    assert not (backup_dir / "usage_20260227_020000.db").exists()
    assert (backup_dir / "usage_20260227_120000.db").exists()
