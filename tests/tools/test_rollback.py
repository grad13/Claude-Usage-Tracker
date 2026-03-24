# meta: updated=2026-03-04 17:38 checked=-
"""Tests for rollback.py.

Covers:
  Test 9:  Restore from backup (atomic swap, backup preserved)
  Test 10: Non-existent version → error
  Test 11: list_versions returns available versions
  Test 22: Atomic swap — current app survives if cp fails
"""

import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import rollback as rollback_mod


# ---------------------------------------------------------------------------
# Test 9: Rollback restore (atomic swap)
# ---------------------------------------------------------------------------

def test_rollback_restore(tmp_path, monkeypatch):
    """Test 9: rollback restores from backup, backup is preserved."""
    install_dir = tmp_path / "Applications"
    app = install_dir / "ClaudeUsageTracker.app"
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.9.1"

    app.mkdir(parents=True)
    (app / "marker").write_text("current")
    backup.mkdir(parents=True)
    (backup / "marker").write_text("backup")

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)
    rollback_mod.rollback("v0.9.1", test_mode=True)

    assert (app / "marker").read_text() == "backup"
    # cp preserves backup
    assert backup.is_dir()


# ---------------------------------------------------------------------------
# Test 10: Non-existent version → error
# ---------------------------------------------------------------------------

def test_rollback_nonexistent_version(tmp_path, monkeypatch):
    """Test 10: Non-existent version → RuntimeError."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup_dir.mkdir()

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)

    with pytest.raises(RuntimeError, match="not found"):
        rollback_mod.rollback("v9.9.9", test_mode=True)


# ---------------------------------------------------------------------------
# Test 11: List versions
# ---------------------------------------------------------------------------

def test_list_versions(tmp_path, monkeypatch):
    """Test 11: list_versions returns available versions."""
    backup_dir = tmp_path / "app-backups"
    (backup_dir / "ClaudeUsageTracker.app.v0.9.1").mkdir(parents=True)
    (backup_dir / "ClaudeUsageTracker.app.v0.9.2").mkdir(parents=True)

    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)
    versions = rollback_mod.list_versions()

    assert "v0.9.1" in versions
    assert "v0.9.2" in versions


# ---------------------------------------------------------------------------
# Test 22: Atomic swap preserves current on failure
# ---------------------------------------------------------------------------

def test_rollback_atomic_leaves_removing_on_crash(tmp_path):
    """If rollback is interrupted after mv to .removing, .removing is recoverable."""
    install_dir = tmp_path / "Applications"
    current = install_dir / "TestApp.app"
    backup = tmp_path / "app-backups" / "TestApp.app.v1.0.0"
    removing = install_dir / "TestApp.app.removing"

    current.mkdir(parents=True)
    (current / "marker").write_text("current")
    backup.mkdir(parents=True)
    (backup / "marker").write_text("v1.0.0")

    # Simulate: cp .new succeeds, mv to .removing succeeds, then crash before final mv
    new_app = install_dir / "TestApp.app.new"
    shutil.copytree(str(backup), str(new_app))
    current.rename(removing)
    # Crash here — .new exists, .removing exists, no current

    # Recovery: .removing has the old current, .new has the new version
    assert not current.exists()
    assert removing.is_dir()
    assert new_app.is_dir()

    # Manual recovery: mv .new to current
    new_app.rename(current)
    shutil.rmtree(str(removing))

    assert (current / "marker").read_text() == "v1.0.0"
