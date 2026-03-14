"""Supplement tests for lib/launchservices.py.

Supplement for: tests/tools/test_lib_functions.py

Covers:
  Test 23: deregister_stale_apps — DerivedData apps are deregistered
  Test 24: deregister_stale_apps — Trash apps are deregistered
  Test 25: register_app — calls lsregister -f
  Test 26: dump_widget_registration — widget found
  Test 27: dump_widget_registration — widget not found
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import call, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from launchservices import (
    LSREGISTER,
    deregister_stale_apps,
    dump_widget_registration,
    register_app,
)


# ---------------------------------------------------------------------------
# Test 23: deregister_stale_apps — DerivedData apps are deregistered
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_derived_data(tmp_path):
    """Apps matching DerivedData pattern are deregistered with lsregister -u."""
    dd = tmp_path / "DerivedData"
    # Create matching DerivedData structure
    app_in_dd = dd / "TestApp-abc123" / "Build" / "Products" / "Debug" / "TestApp.app"
    app_in_dd.mkdir(parents=True)

    with patch("launchservices.subprocess.run") as mock_run:
        deregister_stale_apps("TestApp", str(dd))

    # Should have called lsregister -u on the DerivedData app
    mock_run.assert_any_call(
        [LSREGISTER, "-u", str(app_in_dd)],
        capture_output=True,
    )


# ---------------------------------------------------------------------------
# Test 24: deregister_stale_apps — Trash apps are deregistered
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_trash(tmp_path, monkeypatch):
    """Apps in Trash matching the name are deregistered."""
    trash = tmp_path / ".Trash"
    trash_app = trash / "TestApp.app"
    trash_app.mkdir(parents=True)

    monkeypatch.setattr(Path, "home", lambda: tmp_path)

    dd = tmp_path / "DerivedData"
    dd.mkdir()

    with patch("launchservices.subprocess.run") as mock_run:
        deregister_stale_apps("TestApp", str(dd))

    mock_run.assert_any_call(
        [LSREGISTER, "-u", str(trash_app)],
        capture_output=True,
    )


# ---------------------------------------------------------------------------
# Test 25: register_app — calls lsregister -f
# ---------------------------------------------------------------------------

def test_register_app(tmp_path):
    """register_app calls lsregister -f with the app path."""
    app_path = str(tmp_path / "TestApp.app")

    with patch("launchservices.subprocess.run") as mock_run:
        register_app(app_path)

    mock_run.assert_called_once_with(
        [LSREGISTER, "-f", app_path],
        check=True,
    )


# ---------------------------------------------------------------------------
# Test 26: dump_widget_registration — widget found
# ---------------------------------------------------------------------------

def test_dump_widget_registration_found(mock_lsregister_dump):
    """Returns the path line when widget ID is found in lsregister dump."""
    fake_dump = mock_lsregister_dump(
        "com.example.testwidget",
        path="/Applications/TestApp.app/Contents/PlugIns/TestWidget.appex",
    )

    with patch("launchservices.subprocess.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=fake_dump, stderr=""
        )
        result = dump_widget_registration("com.example.testwidget")

    assert result is not None
    assert "/Applications/TestApp.app" in result


# ---------------------------------------------------------------------------
# Test 27: dump_widget_registration — widget not found
# ---------------------------------------------------------------------------

def test_dump_widget_registration_not_found(mock_lsregister_dump):
    """Returns None when widget ID is not in lsregister dump."""
    fake_dump = mock_lsregister_dump("com.example.testwidget")  # no path -> not found

    with patch("launchservices.subprocess.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=fake_dump, stderr=""
        )
        result = dump_widget_registration("com.example.testwidget")

    assert result is None
