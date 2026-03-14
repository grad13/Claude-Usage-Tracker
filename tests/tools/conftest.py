"""Shared fixtures for tools tests."""

import os
import sqlite3
import subprocess
import time
from pathlib import Path
from unittest.mock import MagicMock

import pytest


@pytest.fixture
def usage_db(tmp_path):
    """Create an empty DB with the same schema as usage.db."""
    db_path = tmp_path / "usage.db"
    conn = sqlite3.connect(str(db_path))
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
    return db_path


@pytest.fixture
def app_dir(tmp_path):
    """Create a TestApp.app directory structure with Contents/."""
    app = tmp_path / "TestApp.app" / "Contents"
    app.mkdir(parents=True)
    return tmp_path / "TestApp.app"


@pytest.fixture
def make_run_result():
    """Factory for subprocess.CompletedProcess mock."""

    def _make(returncode=0, stdout="", stderr=""):
        r = MagicMock(spec=subprocess.CompletedProcess)
        r.returncode = returncode
        r.stdout = stdout
        r.stderr = stderr
        return r

    return _make


@pytest.fixture
def make_widget_binary():
    """Factory for creating fake widget binary under an app directory."""

    def _make(app_dir, size=1024, mtime_offset=0):
        widget_bin = (
            app_dir
            / "Contents"
            / "PlugIns"
            / "ClaudeUsageTrackerWidgetExtension.appex"
            / "Contents"
            / "MacOS"
            / "ClaudeUsageTrackerWidgetExtension"
        )
        widget_bin.parent.mkdir(parents=True, exist_ok=True)
        widget_bin.write_bytes(b"\x00" * size)
        if mtime_offset != 0:
            t = time.time() + mtime_offset
            os.utime(widget_bin, (t, t))
        return widget_bin

    return _make


@pytest.fixture
def usage_db_with_rows(tmp_path):
    """Factory for creating usage.db with N rows (production schema)."""

    def _make(n_rows=10):
        db_path = tmp_path / "usage.db"
        conn = sqlite3.connect(str(db_path))
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS hourly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS weekly_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resets_at INTEGER NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS usage_log (
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
        for i in range(n_rows):
            conn.execute(
                "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (?, ?)",
                (1000 + i, 50.0),
            )
        conn.commit()
        conn.close()
        return db_path

    return _make


@pytest.fixture
def make_app_with_version():
    """Factory for creating .app with optional Info.plist version."""

    def _make(install_dir, app_name, version=None):
        import plistlib

        app_dir = install_dir / f"{app_name}.app" / "Contents"
        app_dir.mkdir(parents=True, exist_ok=True)
        if version is not None:
            plist_path = app_dir / "Info.plist"
            with open(plist_path, "wb") as f:
                plistlib.dump({"CFBundleShortVersionString": version}, f)
        return install_dir / f"{app_name}.app"

    return _make


@pytest.fixture
def mock_lsregister_dump():
    """Factory for lsregister -dump output.

    Matches the format used in test_launchservices_supplement.py:
    "path:    <path>\\nname:    ...\\nplugin Identifiers:         <id>\\n"
    """

    def _make(widget_id, path=None):
        if path:
            return (
                f"path:    {path}\n"
                f"name:    TestWidget\n"
                f"plugin Identifiers:         {widget_id}\n"
            )
        return "path:    /Applications/SomeOtherApp.app\n" "name:    SomeOtherApp\n"

    return _make


