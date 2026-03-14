"""Subprocess runner with consistent logging and error handling."""
from __future__ import annotations

import subprocess
import sys


def run(
    cmd: list[str],
    *,
    check: bool = True,
    label: str = "",
    allow_fail: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run a subprocess with logging.

    - check=True (default): raise RuntimeError on non-zero exit
    - allow_fail=True: log WARNING but don't raise
    - check=False, allow_fail=False: log WARNING (same as allow_fail)
    """
    result = subprocess.run(cmd, capture_output=True, text=True)
    prefix = f"[{label}] " if label else ""
    if result.returncode != 0:
        msg = f"{prefix}rc={result.returncode}: {result.stderr.strip()}"
        if check and not allow_fail:
            raise RuntimeError(msg)
        print(f"WARNING: {msg}", file=sys.stderr)
    return result
