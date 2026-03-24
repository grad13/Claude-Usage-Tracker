# meta: updated=2026-03-04 17:53 checked=-
"""Supplement tests for rollback.py.

Supplement for: tests/tools/test_rollback.py

Covers:
  Test 36: Permission check — no write permission → RuntimeError
  Test 37: Leftover .new cleanup on entry
  Test 38: Leftover .removing cleanup on entry
"""

import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import rollback as rollback_mod


# ---------------------------------------------------------------------------
# Test 36: Permission check — no write permission → RuntimeError
# ---------------------------------------------------------------------------

def test_rollback_permission_denied(tmp_path, monkeypatch):
    """Rollback raises RuntimeError when INSTALL_DIR is not writable."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.9.0"
    backup.mkdir(parents=True)

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)

    # Make install_dir read-only
    install_dir.chmod(0o555)

    try:
        with pytest.raises(RuntimeError, match="Cannot write"):
            rollback_mod.rollback("v0.9.0", test_mode=True)
    finally:
        # Restore permissions for cleanup
        install_dir.chmod(0o755)


# ---------------------------------------------------------------------------
# Test 37: Leftover .new cleanup on entry
# ---------------------------------------------------------------------------

def test_rollback_cleans_leftover_new(tmp_path, monkeypatch):
    """Rollback removes leftover .new from a previous failed run."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.9.0"
    backup.mkdir(parents=True)
    (backup / "marker").write_text("backup_content")

    # Create current app
    current = install_dir / "ClaudeUsageTracker.app"
    current.mkdir()

    # Create leftover .new
    leftover_new = install_dir / "ClaudeUsageTracker.app.new"
    leftover_new.mkdir()
    (leftover_new / "stale").write_text("leftover")

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)

    rollback_mod.rollback("v0.9.0", test_mode=True)

    # Leftover .new should be gone (replaced by backup content)
    assert not leftover_new.exists() or not (leftover_new / "stale").exists()
    # Current app should have backup content
    assert (current / "marker").read_text() == "backup_content"


# ---------------------------------------------------------------------------
# Test 38: Leftover .removing cleanup on entry
# ---------------------------------------------------------------------------

def test_rollback_cleans_leftover_removing(tmp_path, monkeypatch):
    """Rollback removes leftover .removing from a previous interrupted run."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.9.0"
    backup.mkdir(parents=True)
    (backup / "marker").write_text("backup_content")

    # No current app, but leftover .removing
    leftover_removing = install_dir / "ClaudeUsageTracker.app.removing"
    leftover_removing.mkdir()
    (leftover_removing / "stale").write_text("removing_leftover")

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)

    rollback_mod.rollback("v0.9.0", test_mode=True)

    # Leftover .removing should be cleaned up
    assert not leftover_removing.exists()
    # Current app should have backup content
    current = install_dir / "ClaudeUsageTracker.app"
    assert (current / "marker").read_text() == "backup_content"
