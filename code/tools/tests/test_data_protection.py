"""Tests for data protection logic in build-and-install.sh and data-protection.sh.

Covers:
  Test 1-4:  Lost row detection SQL (build-and-install.sh L162-166)
  Test 5:    DB backup rotation (build-and-install.sh L31)
  Test 12-15: File protection via snapshot/restore (data-protection.sh)
"""

import os
import sqlite3
import subprocess
import time

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
        # Set mtime so file 01 is oldest, 12 is newest
        mtime = time.time() - (13 - i) * 60
        os.utime(f, (mtime, mtime))

    # Same rotation logic as build-and-install.sh L31
    subprocess.run(
        f'ls -t "{backup_dir}"/usage_*.db 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true',
        shell=True,
    )

    remaining = sorted(backup_dir.glob("usage_*.db"))
    assert len(remaining) == 10

    # Oldest 2 (01, 02) should be deleted
    assert not (backup_dir / "usage_20260227_010000.db").exists()
    assert not (backup_dir / "usage_20260227_020000.db").exists()
    # Newest (12) should remain
    assert (backup_dir / "usage_20260227_120000.db").exists()


# ---------------------------------------------------------------------------
# Test 12-15: File protection (snapshot_file / restore_file_if_changed)
# ---------------------------------------------------------------------------

def _run_snapshot_restore(script_dir, file_path, bash_mutation):
    """Run snapshot → mutation → restore in a single bash process.

    data-protection.sh uses shell variables (_SNAPSHOT_HASH_*) to pass state
    between snapshot_file and restore_file_if_changed, so they must run in
    the same process.

    Args:
        bash_mutation: A bash command string to execute between snapshot and restore.
                       Use empty string for no mutation.

    Returns:
        The exit code of restore_file_if_changed.
    """
    lib_path = script_dir / "lib" / "data-protection.sh"
    script = f"""
        source "{lib_path}"
        snapshot_file "{file_path}"
        {bash_mutation}
        restore_file_if_changed "{file_path}"
    """
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
    )
    return result.returncode


@pytest.mark.parametrize(
    "scenario,original,bash_mutation,expected_rc,expected_content",
    [
        # Test 12: overwrite → restore returns 1, content restored
        ("overwrite", '{"original":"cookies"}',
         'echo \'{"corrupted":"by-test"}\' > "{file}"', 1, '{"original":"cookies"}'),
        # Test 13: delete → restore returns 2, content restored
        ("deleted", '{"original":"cookies"}',
         'rm "{file}"', 2, '{"original":"cookies"}'),
        # Test 14: file never existed → snapshot + restore skip, returns 0
        ("nonexistent", None, '', 0, None),
        # Test 15: unchanged → restore returns 0, content unchanged
        ("unchanged", '{"unchanged":"data"}', '', 0, '{"unchanged":"data"}'),
    ],
    ids=["overwrite", "deleted", "nonexistent", "unchanged"],
)
def test_file_protection(
    tmp_path, script_dir, scenario, original, bash_mutation, expected_rc, expected_content
):
    target = tmp_path / "session-cookies.json"

    if original is not None:
        target.write_text(original)

    mutation_cmd = bash_mutation.replace("{file}", str(target))
    rc = _run_snapshot_restore(script_dir, str(target), mutation_cmd)
    assert rc == expected_rc

    if expected_content is not None:
        assert target.read_text() == expected_content

    # .backup should always be cleaned up
    assert not (tmp_path / "session-cookies.json.backup").exists()
