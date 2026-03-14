"""Version extraction from .app bundles using plistlib."""
from __future__ import annotations

import plistlib
from pathlib import Path


def get_app_version(app_path: str | Path) -> str:
    """Get CFBundleShortVersionString from an .app bundle.

    Returns "unknown" if Info.plist is missing or unreadable.
    """
    plist_path = Path(app_path) / "Contents" / "Info.plist"
    try:
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)
        return plist.get("CFBundleShortVersionString", "unknown")
    except (FileNotFoundError, plistlib.InvalidFileException, KeyError):
        return "unknown"
    except Exception as e:
        import sys
        print(f"WARNING: Unexpected error reading {plist_path}: {e}", file=sys.stderr)
        return "unknown"
