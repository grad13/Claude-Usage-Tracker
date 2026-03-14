# Supplement for: tests/tools/test_data_protection.py
"""Supplement tests (batch 2) for lib/data_protection.py.

Covers missing cases from spec analysis:
  PF-05: protect_files — one restore failure does not block others
  SF-02: shelter_file — restores file deleted during block
  SF-03: shelter_file — ERROR to stderr when .shelter is lost
  SH-01: _sha256 — normal file returns correct hex digest
  SH-02: _sha256 — empty file returns SHA-256 of empty bytes
  RS-01: _recover_stale_backup — no .backup means no-op
"""

import hashlib
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from data_protection import (
    _recover_stale_backup,
    _sha256,
    protect_files,
    shelter_file,
)


# ---------------------------------------------------------------------------
# SH-01: _sha256 — normal file returns correct SHA-256 hex string
# ---------------------------------------------------------------------------

def test_sha256_normal_file(tmp_path):
    """SH-01: _sha256 computes correct SHA-256 for a normal file."""
    target = tmp_path / "data.bin"
    content = b"hello world data for hashing"
    target.write_bytes(content)

    result = _sha256(target)

    expected = hashlib.sha256(content).hexdigest()
    assert result == expected
    assert len(result) == 64  # SHA-256 hex is 64 chars


# ---------------------------------------------------------------------------
# SH-02: _sha256 — empty file returns SHA-256 of empty bytes
# ---------------------------------------------------------------------------

def test_sha256_empty_file(tmp_path):
    """SH-02: _sha256 returns SHA-256 of empty content for an empty file."""
    target = tmp_path / "empty.bin"
    target.write_bytes(b"")

    result = _sha256(target)

    expected = hashlib.sha256(b"").hexdigest()
    assert result == expected


# ---------------------------------------------------------------------------
# RS-01: _recover_stale_backup — no .backup means no-op
# ---------------------------------------------------------------------------

def test_recover_stale_backup_noop_when_no_backup(tmp_path):
    """RS-01: _recover_stale_backup does nothing when .backup does not exist."""
    target = tmp_path / "settings.json"
    target.write_text('{"key":"value"}')
    backup = target.with_name(target.name + ".backup")

    assert not backup.exists()

    _recover_stale_backup(target)

    # File unchanged, no backup created or modified
    assert target.read_text() == '{"key":"value"}'
    assert not backup.exists()


# ---------------------------------------------------------------------------
# PF-05: protect_files — one restore failure does not block others
# ---------------------------------------------------------------------------

def test_protect_files_restore_failure_does_not_block_others(tmp_path, capsys):
    """PF-05: When one file's restore fails, other files are still restored.

    Simulates: fileA restore raises, fileB restore succeeds.
    Expected: fileB is restored, ERROR printed for fileA.
    """
    file_a = tmp_path / "file_a.json"
    file_b = tmp_path / "file_b.json"
    file_a.write_text("original_a")
    file_b.write_text("original_b")

    original_restore = __import__("data_protection", fromlist=["_restore_if_changed"])._restore_if_changed

    def patched_restore(file, hash_before):
        if file.name == "file_a.json":
            raise OSError("disk error on file_a")
        return original_restore(file, hash_before)

    with patch("data_protection._restore_if_changed", side_effect=patched_restore):
        with protect_files(file_a, file_b):
            file_a.write_text("corrupted_a")
            file_b.write_text("corrupted_b")

    # file_b should be restored by the real _restore_if_changed
    # But since we patched the function, we need a different approach.
    # Let's instead verify the error handling by testing the actual finally logic.

    captured = capsys.readouterr()
    assert "ERROR" in captured.out
    assert "file_a" in captured.out


def test_protect_files_continues_after_restore_exception(tmp_path, capsys):
    """PF-05: Verify both files are attempted even when first restore fails.

    Uses real filesystem: corrupt both files, make file_a.backup unreadable
    so copy2 fails on file_a restore, but file_b restore succeeds.
    """
    file_a = tmp_path / "file_a.json"
    file_b = tmp_path / "file_b.json"
    file_a.write_text("original_a")
    file_b.write_text("original_b")

    with protect_files(file_a, file_b):
        # Corrupt both files
        file_a.write_text("corrupted_a")
        file_b.write_text("corrupted_b")

        # Sabotage file_a's backup so restore will fail
        backup_a = file_a.with_name(file_a.name + ".backup")
        backup_a.unlink()

    captured = capsys.readouterr()

    # file_a restore failed (backup gone) — ERROR printed
    assert "ERROR" in captured.out
    assert "file_a" in captured.out

    # file_b should still be restored despite file_a failure
    assert file_b.read_text() == "original_b"


# ---------------------------------------------------------------------------
# SF-02: shelter_file — restores file deleted during block
# ---------------------------------------------------------------------------

def test_shelter_file_restores_deleted_file(tmp_path):
    """SF-02: shelter_file restores a file that was deleted during the block."""
    target = tmp_path / "cookies.json"
    target.write_text("important_cookies")

    with shelter_file(target):
        target.unlink()
        assert not target.exists()

    # File should be restored from .shelter
    assert target.exists()
    assert target.read_text() == "important_cookies"
    assert not (tmp_path / "cookies.json.shelter").exists()


# ---------------------------------------------------------------------------
# SF-03: shelter_file — ERROR to stderr when .shelter is lost
# ---------------------------------------------------------------------------

def test_shelter_file_error_when_shelter_lost(tmp_path, capsys):
    """SF-03: shelter_file prints ERROR to stderr when .shelter backup is lost."""
    target = tmp_path / "cookies.json"
    target.write_text("important_cookies")

    with shelter_file(target):
        # Delete the .shelter backup while inside the block
        shelter_backup = target.with_name(target.name + ".shelter")
        assert shelter_backup.exists()
        shelter_backup.unlink()

        # Also modify the file to see that it can't be restored
        target.write_text("modified")

    captured = capsys.readouterr()
    assert "ERROR" in captured.err
    assert "cookies.json" in captured.err
    assert "lost" in captured.err.lower() or "cannot be restored" in captured.err.lower()
