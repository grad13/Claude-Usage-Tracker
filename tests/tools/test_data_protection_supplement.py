"""Supplement tests for lib/data_protection.py.

Supplement for: tests/tools/test_data_protection.py

Covers:
  Test 28: _restore_if_changed returns 0 when file unchanged
  Test 29: _restore_if_changed returns 1 when file corrupted
  Test 30: _restore_if_changed returns 2 when file deleted
  Test 31: _restore_if_changed returns 0 when hash_before is None (skipped)
  Test 32: _snapshot raises OSError when backup copy fails (Layer 3)
  Test 38: shelter_file — restores original content after modification
  Test 39: shelter_file — deletes file created during block if file didn't exist
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from data_protection import _restore_if_changed, _sha256, _snapshot, shelter_file


class TestRestoreIfChanged:

    def test_returns_0_unchanged(self, tmp_path):
        """Return 0 when file hash matches — no restore needed."""
        target = tmp_path / "settings.json"
        target.write_text('{"key":"value"}')

        hash_before = _sha256(target)

        backup = target.with_name(target.name + ".backup")
        backup.write_text('{"key":"value"}')

        result = _restore_if_changed(target, hash_before)

        assert result == 0
        assert not backup.exists()

    def test_returns_1_corrupted(self, tmp_path):
        """Return 1 when file was modified — restore from backup."""
        target = tmp_path / "settings.json"
        target.write_text('{"original":"data"}')

        hash_before = _sha256(target)

        backup = target.with_name(target.name + ".backup")
        backup.write_text('{"original":"data"}')

        target.write_text('{"corrupted":"data"}')

        result = _restore_if_changed(target, hash_before)

        assert result == 1
        assert target.read_text() == '{"original":"data"}'
        assert not backup.exists()

    def test_returns_2_deleted(self, tmp_path):
        """Return 2 when file was deleted — restore from backup."""
        target = tmp_path / "settings.json"
        target.write_text('{"original":"data"}')

        hash_before = _sha256(target)

        backup = target.with_name(target.name + ".backup")
        backup.write_text('{"original":"data"}')

        target.unlink()

        result = _restore_if_changed(target, hash_before)

        assert result == 2
        assert target.read_text() == '{"original":"data"}'
        assert not backup.exists()

    def test_returns_0_skipped(self, tmp_path):
        """Return 0 when hash_before is None (file didn't exist at snapshot time)."""
        target = tmp_path / "nonexistent.json"

        result = _restore_if_changed(target, None)

        assert result == 0


class TestSnapshot:

    def test_raises_on_copy_failure(self, tmp_path):
        """_snapshot raises OSError if backup file is not created (Layer 3)."""
        target = tmp_path / "settings.json"
        target.write_text('{"data":"value"}')

        with patch("data_protection.shutil.copy2"):
            with pytest.raises(OSError, match="Failed to create backup"):
                _snapshot(target)


class TestShelterFile:

    def test_restores_unconditionally(self, tmp_path):
        """shelter_file restores original content silently even when file is modified."""
        f = tmp_path / "cookies.json"
        f.write_text("original")

        with shelter_file(f):
            f.write_text("modified by test")

        assert f.read_text() == "original"
        assert not (tmp_path / "cookies.json.shelter").exists()

    def test_nonexistent(self, tmp_path):
        """shelter_file does nothing for a file that doesn't exist."""
        f = tmp_path / "missing.json"

        with shelter_file(f):
            f.write_text("created during test")

        assert not f.exists()
