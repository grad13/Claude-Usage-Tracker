"""Subprocess runner with consistent logging and error handling."""
from __future__ import annotations

import subprocess
import sys


def run(
    cmd: list[str],
    *,
    on_error: str = "raise",
    label: str = "",
) -> subprocess.CompletedProcess[str]:
    """Run a subprocess with logging.

    on_error:
      - "raise" (default): raise RuntimeError on non-zero exit
      - "warn": log WARNING to stderr but don't raise
    """
    result = subprocess.run(cmd, capture_output=True, text=True)
    prefix = f"[{label}] " if label else ""
    if result.returncode != 0:
        msg = f"{prefix}rc={result.returncode}: {result.stderr.strip()}"
        if on_error == "raise":
            raise RuntimeError(msg)
        print(f"WARNING: {msg}", file=sys.stderr)
    return result
