# meta: updated=2026-03-26 checked=-
"""Tests for cleanup_stale_derived_data().

Covers:
  CS-01: Stale DD deleted, current DD kept
  CS-02: Only current DD exists — no deletion
  CS-03: DD without info.plist — deleted as orphan
  CS-04: info.plist read error — skipped
  CS-05: DERIVED_DATA does not exist — noop
  CS-06: rmtree failure — WARNING, continues
  CS-07: info.plist without WorkspacePath key — deleted as orphan
"""

import plistlib
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

import build_and_install as bai


def _create_dd_dir(base: Path, suffix: str, workspace_path: str) -> Path:
    """Create a fake DerivedData directory with info.plist."""
    dd = base / f"ClaudeUsageTracker-{suffix}"
    dd.mkdir(parents=True)
    info_plist = dd / "info.plist"
    with open(info_plist, "wb") as f:
        plistlib.dump({"WorkspacePath": workspace_path}, f)
    return dd


class TestCleanupStaleDerivedData:

    def test_deletes_stale_keeps_current(self, tmp_path, monkeypatch):
        """CS-01: Stale DD is deleted, current DD is kept."""
        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()
        current = _create_dd_dir(dd_base, "current", str(tmp_path / "myproject"))
        stale = _create_dd_dir(dd_base, "old", "/other/path")

        monkeypatch.setattr(bai, "DERIVED_DATA", dd_base)
        monkeypatch.setattr(bai, "PROJECT_DIR", tmp_path / "myproject")
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        bai.cleanup_stale_derived_data()

        assert current.exists()
        assert not stale.exists()

    def test_no_deletion_when_only_current(self, tmp_path, monkeypatch):
        """CS-02: Only current DD exists — nothing deleted."""
        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()
        current = _create_dd_dir(dd_base, "current", str(tmp_path / "myproject"))

        monkeypatch.setattr(bai, "DERIVED_DATA", dd_base)
        monkeypatch.setattr(bai, "PROJECT_DIR", tmp_path / "myproject")
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        bai.cleanup_stale_derived_data()

        assert current.exists()

    def test_deletes_orphan_without_plist(self, tmp_path, monkeypatch, capsys):
        """CS-03: DD without info.plist is deleted as orphan."""
        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()
        orphan = dd_base / "ClaudeUsageTracker-orphan"
        orphan.mkdir()
        # No info.plist created

        monkeypatch.setattr(bai, "DERIVED_DATA", dd_base)
        monkeypatch.setattr(bai, "PROJECT_DIR", tmp_path / "myproject")
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        bai.cleanup_stale_derived_data()

        assert not orphan.exists()
        captured = capsys.readouterr()
        assert "no info.plist" in captured.out

    def test_skips_on_plist_read_error(self, tmp_path, monkeypatch, capsys):
        """CS-04: Unreadable info.plist — directory is skipped (not deleted)."""
        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()
        bad = dd_base / "ClaudeUsageTracker-bad"
        bad.mkdir()
        plist = bad / "info.plist"
        plist.write_text("this is not valid plist data")

        monkeypatch.setattr(bai, "DERIVED_DATA", dd_base)
        monkeypatch.setattr(bai, "PROJECT_DIR", tmp_path / "myproject")
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        bai.cleanup_stale_derived_data()

        assert bad.exists()  # Skipped, not deleted
        captured = capsys.readouterr()
        assert "Failed to read" in captured.out

    def test_noop_when_derived_data_missing(self, tmp_path, monkeypatch):
        """CS-05: DERIVED_DATA does not exist — no error."""
        monkeypatch.setattr(bai, "DERIVED_DATA", tmp_path / "nonexistent")

        bai.cleanup_stale_derived_data()  # Should not raise

    def test_continues_on_rmtree_failure(self, tmp_path, monkeypatch, capsys):
        """CS-06: rmtree failure logs WARNING and continues to next dir."""
        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()
        stale1 = _create_dd_dir(dd_base, "stale1", "/old/path1")
        stale2 = _create_dd_dir(dd_base, "stale2", "/old/path2")

        call_count = 0
        original_rmtree = shutil.rmtree

        def failing_rmtree_first(path, *args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise PermissionError("simulated permission error")
            original_rmtree(path, *args, **kwargs)

        monkeypatch.setattr(bai, "DERIVED_DATA", dd_base)
        monkeypatch.setattr(bai, "PROJECT_DIR", tmp_path / "myproject")
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")
        monkeypatch.setattr(shutil, "rmtree", failing_rmtree_first)

        bai.cleanup_stale_derived_data()

        captured = capsys.readouterr()
        assert "Failed to delete" in captured.out
        # One should have failed, the other succeeded
        assert call_count == 2

    def test_deletes_orphan_without_workspace_key(self, tmp_path, monkeypatch, capsys):
        """CS-07: info.plist exists but WorkspacePath key is missing — deleted."""
        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()
        orphan = dd_base / "ClaudeUsageTracker-nokey"
        orphan.mkdir()
        plist = orphan / "info.plist"
        with open(plist, "wb") as f:
            plistlib.dump({"SomeOtherKey": "value"}, f)

        monkeypatch.setattr(bai, "DERIVED_DATA", dd_base)
        monkeypatch.setattr(bai, "PROJECT_DIR", tmp_path / "myproject")
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        bai.cleanup_stale_derived_data()

        assert not orphan.exists()
        captured = capsys.readouterr()
        assert "no WorkspacePath" in captured.out
