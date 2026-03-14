# Supplement for: tests/tools/test_rollback.py
"""Supplement tests (2) for rollback.py.

Covers gaps identified in analysis/rollback.md:
  LV-01: APP_BACKUP_DIR does not exist -> []
  LV-03: Only files (no directories) in backup dir -> []
  RB-05: Current .app absent -> rename-only (no move-to-removing)
  RB-06: copytree FileExistsError -> rmtree + retry
  MN-01: No args -> version list + exit(1)
  MN-02: Args -> rollback() called
  MN-03: RuntimeError -> stderr + exit(1)
"""

import shutil
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(_PROJECT_ROOT / "code" / "tools" / "lib"))
sys.path.insert(0, str(_PROJECT_ROOT / "code" / "tools"))

import rollback as rollback_mod


# ---------------------------------------------------------------------------
# LV-01: APP_BACKUP_DIR does not exist -> []
# ---------------------------------------------------------------------------

def test_list_versions_no_backup_dir(tmp_path, monkeypatch):
    """LV-01: list_versions returns [] when APP_BACKUP_DIR does not exist."""
    nonexistent = tmp_path / "no-such-dir"
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", nonexistent)

    assert rollback_mod.list_versions() == []


# ---------------------------------------------------------------------------
# LV-03: Only files (no directories) in backup dir -> []
# ---------------------------------------------------------------------------

def test_list_versions_files_only(tmp_path, monkeypatch):
    """LV-03: list_versions returns [] when backup dir has only files, no dirs."""
    backup_dir = tmp_path / "app-backups"
    backup_dir.mkdir()
    # Create files that match the glob pattern but are not directories
    (backup_dir / "ClaudeUsageTracker.app.v1.0.0").write_text("not a dir")
    (backup_dir / "ClaudeUsageTracker.app.v2.0.0").write_text("not a dir")

    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)
    monkeypatch.setattr(rollback_mod, "APP_NAME", "ClaudeUsageTracker")

    assert rollback_mod.list_versions() == []


# ---------------------------------------------------------------------------
# RB-05: Current .app absent -> rename-only (no move-to-removing step)
# ---------------------------------------------------------------------------

def test_rollback_no_current_app(tmp_path, monkeypatch):
    """RB-05: When current .app does not exist, rollback copies backup and renames .new -> .app."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.8.0"
    backup.mkdir(parents=True)
    (backup / "marker").write_text("v0.8.0-content")

    # No current app exists at install_dir / "ClaudeUsageTracker.app"

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)

    rollback_mod.rollback("v0.8.0", test_mode=True)

    current = install_dir / "ClaudeUsageTracker.app"
    assert current.is_dir()
    assert (current / "marker").read_text() == "v0.8.0-content"
    # No .removing should exist since there was no current app to move
    removing = install_dir / "ClaudeUsageTracker.app.removing"
    assert not removing.exists()


# ---------------------------------------------------------------------------
# RB-06: copytree FileExistsError -> rmtree + retry
# ---------------------------------------------------------------------------

def test_rollback_copytree_file_exists_error_retries(tmp_path, monkeypatch):
    """RB-06: If copytree raises FileExistsError, rollback retries after rmtree."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.7.0"
    backup.mkdir(parents=True)
    (backup / "marker").write_text("v0.7.0-content")

    current = install_dir / "ClaudeUsageTracker.app"
    current.mkdir()

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)

    original_copytree = shutil.copytree
    call_count = 0

    def copytree_fail_once(src, dst, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            # Simulate race condition: .new appears between cleanup and copytree
            Path(dst).mkdir(parents=True, exist_ok=True)
            raise FileExistsError(f"[Errno 17] File exists: '{dst}'")
        return original_copytree(src, dst, **kwargs)

    monkeypatch.setattr(shutil, "copytree", copytree_fail_once)

    rollback_mod.rollback("v0.7.0", test_mode=True)

    assert call_count == 2, "copytree should have been called twice (fail + retry)"
    assert (current / "marker").read_text() == "v0.7.0-content"


# ---------------------------------------------------------------------------
# MN-01: No args -> version list + exit(1)
# ---------------------------------------------------------------------------

def test_main_no_args_lists_versions_and_exits(tmp_path, monkeypatch):
    """MN-01: main() with no args prints version list and exits with code 1."""
    backup_dir = tmp_path / "app-backups"
    (backup_dir / "ClaudeUsageTracker.app.v0.9.0").mkdir(parents=True)
    (backup_dir / "ClaudeUsageTracker.app.v0.9.1").mkdir(parents=True)

    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)
    monkeypatch.setattr("sys.argv", ["rollback.py"])

    with pytest.raises(SystemExit) as exc_info:
        rollback_mod.main()

    assert exc_info.value.code == 1


# ---------------------------------------------------------------------------
# MN-02: Args -> rollback() called
# ---------------------------------------------------------------------------

def test_main_with_arg_calls_rollback(tmp_path, monkeypatch):
    """MN-02: main() with version arg calls rollback() for that version."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()
    backup_dir = tmp_path / "app-backups"
    backup = backup_dir / "ClaudeUsageTracker.app.v0.9.0"
    backup.mkdir(parents=True)
    (backup / "marker").write_text("v0.9.0-content")

    current = install_dir / "ClaudeUsageTracker.app"
    current.mkdir()

    monkeypatch.setattr(rollback_mod, "INSTALL_DIR", install_dir)
    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)
    monkeypatch.setattr("sys.argv", ["rollback.py", "v0.9.0"])
    # Set ROLLBACK_TEST_MODE so main() passes test_mode=True
    monkeypatch.setenv("ROLLBACK_TEST_MODE", "1")

    rollback_mod.main()

    assert (current / "marker").read_text() == "v0.9.0-content"


# ---------------------------------------------------------------------------
# MN-03: RuntimeError -> stderr + exit(1)
# ---------------------------------------------------------------------------

def test_main_runtime_error_exits_with_error(tmp_path, monkeypatch, capsys):
    """MN-03: When rollback() raises RuntimeError, __main__ block prints to stderr and exits(1)."""
    backup_dir = tmp_path / "app-backups"
    backup_dir.mkdir()

    monkeypatch.setattr(rollback_mod, "APP_BACKUP_DIR", backup_dir)
    monkeypatch.setattr("sys.argv", ["rollback.py", "v9.9.9"])
    monkeypatch.setenv("ROLLBACK_TEST_MODE", "1")

    # Simulate the if __name__ == "__main__" block behavior
    with pytest.raises(SystemExit) as exc_info:
        try:
            rollback_mod.main()
        except RuntimeError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            sys.exit(1)

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert "not found" in captured.err
