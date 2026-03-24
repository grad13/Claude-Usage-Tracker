# meta: updated=2026-03-15 08:04 checked=-
# Supplement for: tests/tools/test_launchservices.py
"""Supplement tests for lib/launchservices.py — missing cases from spec analysis.

Covers:
  DS-06: Trash not exists — skip Trash scan
  DS-07: Non-directory entry in DerivedData glob — skipped by is_dir()
  DS-08: lsregister -u failure — WARNING + continue
  RA-02: lsregister -f failure — RuntimeError
  DW-03: widget_id found + no path line (hit ---- boundary)
  DW-04: widget_id found + no path line (hit start of dump)
  DW-05: lsregister -dump failure — empty stdout → None
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from launchservices import (
    LSREGISTER,
    deregister_stale_apps,
    dump_widget_registration,
    register_app,
)


# ---------------------------------------------------------------------------
# DS-06: Trash not exists — Trash scan is skipped
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_trash_not_exists(tmp_path, monkeypatch):
    """DS-06: When ~/.Trash does not exist, Trash scan is skipped entirely."""
    # tmp_path has no .Trash directory
    monkeypatch.setattr(Path, "home", lambda: tmp_path)

    dd = tmp_path / "DerivedData"
    dd.mkdir()
    # No matching apps in DerivedData either

    with patch("launchservices.run") as mock_run:
        deregister_stale_apps("TestApp", str(dd))

    # No lsregister calls at all — both DD and Trash are empty/missing
    mock_run.assert_not_called()


# ---------------------------------------------------------------------------
# DS-07: Non-directory entry in DerivedData glob — skipped by is_dir()
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_file_in_derived_data(tmp_path):
    """DS-07: Files (not directories) matching glob pattern are skipped."""
    dd = tmp_path / "DerivedData"
    # Create the path but make the .app a file, not a directory
    parent = dd / "TestApp-abc123" / "Build" / "Products" / "Debug"
    parent.mkdir(parents=True)
    (parent / "TestApp.app").write_text("not a directory")

    with patch("launchservices.run") as mock_run:
        deregister_stale_apps("TestApp", str(dd))

    # File should be skipped by is_dir() check — no lsregister calls
    mock_run.assert_not_called()


# ---------------------------------------------------------------------------
# DS-08: lsregister -u failure — WARNING output + continue
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_lsregister_failure(tmp_path, monkeypatch, capsys):
    """DS-08: lsregister -u failure emits WARNING but does not raise."""
    dd = tmp_path / "DerivedData"
    app_dir = dd / "TestApp-abc123" / "Build" / "Products" / "Debug" / "TestApp.app"
    app_dir.mkdir(parents=True)

    # Ensure Trash is also checked (no crash after DD failure)
    monkeypatch.setattr(Path, "home", lambda: tmp_path)

    with patch("launchservices.run") as mock_run:
        # Simulate run() with on_error="warn" — it prints WARNING but doesn't raise
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=1, stdout="", stderr="error"
        )
        # Should not raise
        deregister_stale_apps("TestApp", str(dd))

    # lsregister -u was called with on_error="warn"
    mock_run.assert_called_with(
        [LSREGISTER, "-u", str(app_dir)],
        on_error="warn",
        label="deregister DD",
    )


# ---------------------------------------------------------------------------
# RA-02: lsregister -f failure — RuntimeError
# ---------------------------------------------------------------------------

def test_register_app_failure_raises():
    """RA-02: lsregister -f failure raises RuntimeError via on_error='raise'."""
    with patch("launchservices.run") as mock_run:
        mock_run.side_effect = RuntimeError("[register app] rc=1: failed")
        with pytest.raises(RuntimeError, match="rc=1"):
            register_app("/Applications/TestApp.app")

    mock_run.assert_called_once_with(
        [LSREGISTER, "-f", "/Applications/TestApp.app"],
        label="register app",
    )


# ---------------------------------------------------------------------------
# DW-03: widget_id found + no path line (hit ---- boundary)
# ---------------------------------------------------------------------------

def test_dump_widget_registration_no_path_boundary(capsys):
    """DW-03: widget_id found but path line missing — hit ---- boundary."""
    fake_dump = (
        "------------------------------------------------------------\n"
        "name:    TestWidget\n"
        "plugin Identifiers:         com.example.testwidget\n"
    )

    with patch("launchservices.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=fake_dump, stderr=""
        )
        result = dump_widget_registration("com.example.testwidget")

    assert result is None
    captured = capsys.readouterr()
    assert "WARNING" in captured.out
    assert "com.example.testwidget" in captured.out


# ---------------------------------------------------------------------------
# DW-04: widget_id found + no path line (hit start of dump)
# ---------------------------------------------------------------------------

def test_dump_widget_registration_no_path_start():
    """DW-04: widget_id found but path line missing — hit start of dump."""
    # No ---- separator before the entry, and no path: line
    fake_dump = (
        "name:    TestWidget\n"
        "plugin Identifiers:         com.example.testwidget\n"
    )

    with patch("launchservices.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=fake_dump, stderr=""
        )
        result = dump_widget_registration("com.example.testwidget")

    assert result is None


# ---------------------------------------------------------------------------
# DW-05: lsregister -dump failure — empty stdout → None
# ---------------------------------------------------------------------------

def test_dump_widget_registration_dump_failure():
    """DW-05: lsregister -dump fails — returns CompletedProcess with empty stdout → None."""
    with patch("launchservices.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=1, stdout="", stderr="dump failed"
        )
        result = dump_widget_registration("com.example.testwidget")

    assert result is None
