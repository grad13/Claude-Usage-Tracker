"""Tests for data_protection module.

Covers:
  Test 12-15: File protection via protect_files context manager
  Test 16:    exit (exception) auto-restore via try/finally
  Test 17:    Stale .backup recovery (crash recovery)
  Test 18:    protect_files with nonexistent files
  Test 19:    Nested exception in restore doesn't suppress original
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))

from data_protection import protect_files, _sha256, _recover_stale_backup


# ---------------------------------------------------------------------------
# Test 12-15: File protection (protect_files context manager)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "scenario,original,mutate,expected_content",
    [
        # Test 12: overwrite → restored
        ("overwrite", '{"original":"cookies"}',
         lambda p: p.write_text('{"corrupted":"by-test"}'),
         '{"original":"cookies"}'),
        # Test 13: delete → restored
        ("deleted", '{"original":"cookies"}',
         lambda p: p.unlink(),
         '{"original":"cookies"}'),
        # Test 14: file never existed → no-op
        ("nonexistent", None,
         lambda p: None,
         None),
        # Test 15: unchanged → unchanged
        ("unchanged", '{"unchanged":"data"}',
         lambda p: None,
         '{"unchanged":"data"}'),
    ],
    ids=["overwrite", "deleted", "nonexistent", "unchanged"],
)
def test_file_protection(tmp_path, scenario, original, mutate, expected_content):
    target = tmp_path / "session-cookies.json"

    if original is not None:
        target.write_text(original)

    with protect_files(target):
        mutate(target)

    if expected_content is not None:
        assert target.read_text() == expected_content

    # .backup should always be cleaned up
    assert not (tmp_path / "session-cookies.json.backup").exists()


# ---------------------------------------------------------------------------
# Test 16: Exception auto-restore (the sign-out bug fix)
# ---------------------------------------------------------------------------

def test_exception_auto_restore(tmp_path):
    """protect_files restores even when an exception occurs (try/finally).

    This is the core fix for the sign-out bug: previously, exit 1 before
    restore_file_if_changed left corrupted files behind.
    """
    target = tmp_path / "session-cookies.json"
    target.write_text('{"good":"cookies"}')

    with pytest.raises(RuntimeError, match="test failure"):
        with protect_files(target):
            target.write_text('{"corrupted":"by-test"}')
            raise RuntimeError("test failure")

    # File restored despite exception
    assert target.read_text() == '{"good":"cookies"}'
    assert not target.with_name(target.name + ".backup").exists()


# ---------------------------------------------------------------------------
# Test 17: Stale .backup recovery (crash recovery — Layer 2)
# ---------------------------------------------------------------------------

def test_stale_backup_recovery(tmp_path):
    """Reproduce the sign-out bug scenario:

    Run 1: snapshot(GOOD) → corruption → crash (no restore)
           .backup=GOOD, file=BAD

    Run 2: protect_files detects stale .backup → restores GOOD before snapshot
           Result: file=GOOD after protection
    """
    target = tmp_path / "session-cookies.json"
    backup = target.with_name(target.name + ".backup")

    # Simulate Run 1 crash state
    target.write_text('{"corrupted":"by-test"}')
    backup.write_text('{"good":"cookies"}')

    # Run 2: protect_files should recover from stale .backup
    with protect_files(target):
        # Inside protection, file should already be restored to GOOD
        assert target.read_text() == '{"good":"cookies"}'

    # After protection, file is still GOOD
    assert target.read_text() == '{"good":"cookies"}'
    assert not backup.exists()


# ---------------------------------------------------------------------------
# Test 18: Multiple files protected simultaneously
# ---------------------------------------------------------------------------

def test_multiple_files_protected(tmp_path):
    """protect_files handles multiple files; all restored on exception."""
    settings = tmp_path / "settings.json"
    cookies = tmp_path / "cookies.json"
    settings.write_text('{"setting":"value"}')
    cookies.write_text('{"cookie":"value"}')

    with pytest.raises(RuntimeError):
        with protect_files(settings, cookies):
            settings.write_text('{"corrupted":"settings"}')
            cookies.unlink()
            raise RuntimeError("boom")

    assert settings.read_text() == '{"setting":"value"}'
    assert cookies.read_text() == '{"cookie":"value"}'


# ---------------------------------------------------------------------------
# Test 19: Full sign-out bug reproduction (end-to-end)
# ---------------------------------------------------------------------------

def test_signout_bug_full_sequence(tmp_path):
    """End-to-end reproduction of the sign-out bug with the fix.

    Sequence:
      Run 1: protect → corrupt → exception (simulates test failure)
             With try/finally, file is restored automatically.
      Run 2: protect → corrupt → normal exit
             No stale .backup, normal restore.

    Before fix: Run 1 left .backup, Run 2 overwrote it → sign out.
    After fix: Run 1 restores via finally, Run 2 works normally.
    """
    cookies = tmp_path / "session-cookies.json"
    cookies.write_text('{"good":"cookies"}')

    # Run 1: test failure (exception)
    with pytest.raises(RuntimeError):
        with protect_files(cookies):
            cookies.write_text('{"corrupted":"run1"}')
            raise RuntimeError("xcodebuild test failed")

    # After Run 1: cookies restored, no .backup
    assert cookies.read_text() == '{"good":"cookies"}'
    assert not cookies.with_name(cookies.name + ".backup").exists()

    # Run 2: normal flow
    with protect_files(cookies):
        cookies.write_text('{"corrupted":"run2"}')

    # After Run 2: cookies restored
    assert cookies.read_text() == '{"good":"cookies"}'
