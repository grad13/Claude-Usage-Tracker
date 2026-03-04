"""Tests for rollback.sh.

Covers:
  Test 9:  Restore from backup (cp -R, backup preserved)
  Test 10: Non-existent version → exit 1
  Test 11: No argument → list available versions, exit 1
"""

import os
import subprocess

import pytest


def _run_rollback(script_dir, install_dir, version=None):
    """Run rollback.sh with ROLLBACK_TEST_MODE=1."""
    cmd = [str(script_dir / "rollback.sh")]
    if version is not None:
        cmd.append(version)

    env = {
        **os.environ,
        "ROLLBACK_TEST_MODE": "1",
        "INSTALL_DIR": str(install_dir),
    }
    return subprocess.run(cmd, env=env, capture_output=True, text=True)


def test_rollback_restore(tmp_path, script_dir):
    """Test 9: rollback.sh restores from backup, backup is preserved."""
    install_dir = tmp_path / "Applications"
    app = install_dir / "ClaudeUsageTracker.app"
    backup = install_dir / "ClaudeUsageTracker.app.v0.9.1"

    app.mkdir(parents=True)
    (app / "marker").write_text("current")
    backup.mkdir(parents=True)
    (backup / "marker").write_text("backup")

    result = _run_rollback(script_dir, install_dir, "v0.9.1")

    assert result.returncode == 0
    assert (app / "marker").read_text() == "backup"
    # cp -R preserves backup
    assert backup.is_dir()


def test_rollback_nonexistent_version(tmp_path, script_dir):
    """Test 10: Non-existent version → exit 1."""
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()

    result = _run_rollback(script_dir, install_dir, "v9.9.9")

    assert result.returncode == 1


def test_rollback_list_versions(tmp_path, script_dir):
    """Test 11: No argument → list versions, exit 1."""
    install_dir = tmp_path / "Applications"
    (install_dir / "ClaudeUsageTracker.app.v0.9.1").mkdir(parents=True)
    (install_dir / "ClaudeUsageTracker.app.v0.9.2").mkdir(parents=True)

    result = _run_rollback(script_dir, install_dir)

    assert result.returncode == 1
    assert "v0.9.1" in result.stdout + result.stderr
    assert "v0.9.2" in result.stdout + result.stderr
