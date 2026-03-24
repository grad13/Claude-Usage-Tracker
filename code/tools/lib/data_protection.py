# meta: updated=2026-03-15 06:58 checked=-
"""File protection with guaranteed cleanup.

Usage:
    with protect_files(settings_path, cookies_path):
        subprocess.run(["xcodebuild", "test", ...])
        # Even if this raises, finally block restores files automatically.

Three defense layers:
    1. try/finally — guarantees restore on any Python exception or normal exit
    2. Stale .backup detection — recovers from SIGKILL / power loss on next run
    3. cp failure detection — raises on disk full / permission errors
"""

from __future__ import annotations

import hashlib
import shutil
from contextlib import contextmanager
from pathlib import Path


def _sha256(path: Path) -> str:
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _recover_stale_backup(file: Path) -> None:
    """Layer 2: If .backup exists from a crashed previous run, restore it.

    .backup existence without active protection means the previous run
    died before cleanup. The .backup contains the known-good state.
    """
    backup = file.with_name(file.name + ".backup")
    if backup.exists():
        print(f"WARNING: Stale .backup found for {file.name} — restoring from previous run.")
        shutil.copy2(str(backup), str(file))
        backup.unlink()


def _snapshot(file: Path) -> str | None:
    """Take a snapshot: record hash and create .backup.

    Returns the SHA-256 hash, or None if file doesn't exist.
    Raises on cp failure (Layer 3).
    """
    if not file.exists():
        return None

    file_hash = _sha256(file)
    backup = file.with_name(file.name + ".backup")
    try:
        shutil.copy2(str(file), str(backup))
    except OSError as e:
        raise OSError(f"Failed to backup {file}: {e}") from e

    # Verify the copy succeeded (Layer 3)
    if not backup.exists():
        raise OSError(f"Backup created but not found: {backup}")

    return file_hash


def _restore_if_changed(file: Path, hash_before: str | None) -> int:
    """Restore file if changed or deleted since snapshot.

    Returns:
        0: unchanged or skipped (file didn't exist at snapshot time)
        1: restored (file was corrupted)
        2: restored (file was deleted)
    """
    if hash_before is None:
        return 0

    backup = file.with_name(file.name + ".backup")

    if file.exists():
        hash_after = _sha256(file)
        if hash_before != hash_after:
            print(f"WARNING: {file.name} was corrupted — restoring from backup.")
            shutil.copy2(str(backup), str(file))
            backup.unlink()
            return 1
        backup.unlink()
        return 0
    else:
        print(f"WARNING: {file.name} was deleted — restoring from backup.")
        shutil.copy2(str(backup), str(file))
        backup.unlink()
        return 2


@contextmanager
def protect_files(*paths: str | Path):
    """Context manager that protects files from corruption during dangerous operations.

    On entry: creates .backup copies with hash verification.
    On exit (normal or exception): restores any changed/deleted files.
    Stale .backup from crashed previous runs is recovered on entry.

    Usage:
        with protect_files("/path/to/settings.json"):
            subprocess.run(["xcodebuild", "test", ...])
    """
    files = [Path(p) for p in paths]
    snapshots: dict[Path, str | None] = {}

    # Layer 2: recover from any previous crash
    for file in files:
        _recover_stale_backup(file)

    # Take snapshots
    for file in files:
        snapshots[file] = _snapshot(file)

    try:
        yield
    finally:
        # Guaranteed restore — Layer 1 (try/finally)
        for file in files:
            try:
                _restore_if_changed(file, snapshots[file])
            except Exception as e:
                print(f"ERROR: Failed to restore {file.name}: {e}")


@contextmanager
def shelter_file(path: str | Path):
    """Unconditionally backup and restore a file around a block.

    Unlike protect_files, no hash comparison — always restores silently.
    Use for files that are expected to be modified (e.g., cookie files during tests).
    """
    file = Path(path)
    backup = file.with_name(file.name + ".shelter")
    existed = file.exists()
    if existed:
        shutil.copy2(str(file), str(backup))
    try:
        yield
    finally:
        if existed:
            if backup.exists():
                shutil.copy2(str(backup), str(file))
                backup.unlink()
            else:
                import sys
                print(f"ERROR: Shelter backup for {file.name} was lost! "
                      f"Original file cannot be restored.", file=sys.stderr)
        elif not existed and file.exists():
            file.unlink()
