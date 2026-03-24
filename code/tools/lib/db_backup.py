# meta: updated=2026-03-15 06:58 checked=-
"""Database backup utilities for deploy script."""
from __future__ import annotations

import shutil
import sqlite3
from datetime import datetime
from pathlib import Path


def rotate_backups(backup_dir: Path, keep: int = 10) -> None:
    """Rotate backup files, keeping the newest `keep` files."""
    backups = sorted(backup_dir.glob("usage_*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in backups[keep:]:
        old.unlink()


def backup_database(db_path: Path, appgroup_dir: Path) -> tuple[int, Path | None]:
    """Backup usage.db and rotate old backups (keep newest 10).

    Returns (pre_count, backup_path).
    pre_count is -1 if DB read failed (sentinel for error state).
    """
    if not db_path.exists():
        return 0, None

    # Count rows before backup
    try:
        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA query_only = ON")
        pre_count = conn.execute("SELECT COUNT(*) FROM usage_log").fetchone()[0]
        conn.close()
    except sqlite3.Error as e:
        print(f"WARNING: DB pre-count failed ({type(e).__name__}: {e})")
        print(f"         DB may be corrupted. Proceeding with backup anyway.")
        pre_count = -1  # sentinel: distinguishable from "0 rows"

    # Create backup
    backup_dir = appgroup_dir / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_file = backup_dir / f"usage_{datetime.now():%Y%m%d_%H%M%S}.db"
    shutil.copy2(str(db_path), str(backup_file))
    count_str = str(pre_count) if pre_count >= 0 else "UNKNOWN (DB error)"
    print(f"==> DB backup: {count_str} rows → {backup_file}")

    rotate_backups(backup_dir)

    return pre_count, backup_file


def check_lost_rows(current_db: str, backup_db: str) -> int:
    """Count rows in backup that are missing from current DB."""
    conn = sqlite3.connect(current_db)
    conn.execute(f"ATTACH '{backup_db}' AS backup")
    lost = conn.execute(
        "SELECT COUNT(*) FROM backup.usage_log "
        "WHERE rowid NOT IN (SELECT rowid FROM main.usage_log)"
    ).fetchone()[0]
    conn.close()
    return lost
