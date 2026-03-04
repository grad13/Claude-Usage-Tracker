"""Shared fixtures for tools tests."""

import sqlite3
from pathlib import Path

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
def script_dir():
    """Return the absolute path to code/tools/."""
    return Path(__file__).parent.parent
