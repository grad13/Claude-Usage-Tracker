"""Supplement tests for find_derived_data_dir() edge cases.

Split from: test_build_and_install_supplement2.py

Covers:
  FD-05: info.plist missing -> returns None
  FD-06: info.plist read error -> returns None
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))

import build_and_install as bai


class TestFindDerivedDataDirEdgeCases:

    def test_info_plist_not_found(self, tmp_path, monkeypatch):
        """FD-05: DerivedData dir exists but info.plist is missing -> returns None."""
        dd = tmp_path / "DerivedData"
        dd.mkdir()
        candidate = dd / "ClaudeUsageTracker-abc123"
        candidate.mkdir()

        monkeypatch.setattr(bai, "DERIVED_DATA", dd)
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        result = bai.find_derived_data_dir()
        assert result is None

    def test_info_plist_read_error(self, tmp_path, monkeypatch):
        """FD-06: info.plist exists but is unreadable -> returns None (exception swallowed)."""
        dd = tmp_path / "DerivedData"
        dd.mkdir()
        candidate = dd / "ClaudeUsageTracker-abc123"
        candidate.mkdir()
        plist = candidate / "info.plist"
        plist.write_text("this is not valid plist data")

        monkeypatch.setattr(bai, "DERIVED_DATA", dd)
        monkeypatch.setattr(bai, "APP_NAME", "ClaudeUsageTracker")

        result = bai.find_derived_data_dir()
        assert result is None
