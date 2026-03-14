"""Tests for find_derived_data_dir().

Covers:
  Test 1: Multiple DerivedData dirs → correct one selected by WorkspacePath
  Test 2: No WorkspacePath match → None (with WARNING)
  Test 3: Empty DerivedData → None
  Test 4: DerivedData dir doesn't exist → None
"""

import plistlib
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))


def _create_dd_dir(base: Path, suffix: str, workspace_path: str) -> Path:
    """Create a fake DerivedData directory with info.plist."""
    dd = base / f"ClaudeUsageTracker-{suffix}"
    dd.mkdir(parents=True)
    info_plist = dd / "info.plist"
    with open(info_plist, "wb") as f:
        plistlib.dump({"WorkspacePath": workspace_path}, f)
    return dd


class TestFindDerivedDataDir:

    def test_selects_correct_project_by_workspace_path(self, tmp_path):
        """Test 1: Selects the dir whose WorkspacePath matches PROJECT_DIR."""
        import build_and_install as bi

        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()

        correct = _create_dd_dir(dd_base, "abc", str(tmp_path / "myproject"))
        _create_dd_dir(dd_base, "xyz", "/other/project")

        with patch.object(bi, "DERIVED_DATA", dd_base), \
             patch.object(bi, "PROJECT_DIR", tmp_path / "myproject"):
            result = bi.find_derived_data_dir()

        assert result == correct

    def test_returns_none_when_no_workspace_match(self, tmp_path, capsys):
        """Test 2: No WorkspacePath match → None + WARNING."""
        import build_and_install as bi

        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()

        _create_dd_dir(dd_base, "old", "/wrong/path")
        _create_dd_dir(dd_base, "new", "/also/wrong")

        with patch.object(bi, "DERIVED_DATA", dd_base), \
             patch.object(bi, "PROJECT_DIR", Path("/nonexistent")):
            result = bi.find_derived_data_dir()

        assert result is None
        captured = capsys.readouterr()
        assert "WARNING" in captured.out

    def test_empty_derived_data(self, tmp_path):
        """Test 3: DerivedData exists but empty → None."""
        import build_and_install as bi

        dd_base = tmp_path / "DerivedData"
        dd_base.mkdir()

        with patch.object(bi, "DERIVED_DATA", dd_base):
            assert bi.find_derived_data_dir() is None

    def test_derived_data_not_exists(self, tmp_path):
        """Test 4: DerivedData directory doesn't exist → None."""
        import build_and_install as bi

        with patch.object(bi, "DERIVED_DATA", tmp_path / "nonexistent"):
            assert bi.find_derived_data_dir() is None
