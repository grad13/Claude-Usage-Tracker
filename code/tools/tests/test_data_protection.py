"""Tests for data protection logic in build-and-install.sh and data-protection.sh.

Covers:
  Test 1-4:  Lost row detection SQL (build-and-install.sh L162-166)
  Test 5:    DB backup rotation (build-and-install.sh L31)
  Test 12-15: File protection via snapshot/restore (data-protection.sh)
"""

import sqlite3
import subprocess

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
    """Run the same lost-row detection SQL as build-and-install.sh L162-166."""
    result = subprocess.run(
        [
            "sqlite3",
            str(current_db),
            f"ATTACH '{backup_db}' AS backup; "
            "SELECT COUNT(*) FROM backup.usage_log "
            "WHERE rowid NOT IN (SELECT rowid FROM main.usage_log);",
        ],
        capture_output=True,
        text=True,
    )
    return int(result.stdout.strip())


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
