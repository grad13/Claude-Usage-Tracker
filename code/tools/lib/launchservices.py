"""LaunchServices utilities for app registration management."""
from __future__ import annotations

from pathlib import Path

from runner import run

LSREGISTER = (
    "/System/Library/Frameworks/CoreServices.framework"
    "/Versions/Current/Frameworks/LaunchServices.framework"
    "/Versions/Current/Support/lsregister"
)


def deregister_stale_apps(app_name: str, derived_data: str) -> None:
    """Deregister stale app copies from DerivedData and Trash.

    Raises ValueError if app_name or derived_data is empty.
    Deregistration failures are logged but not fatal (idempotent operation).
    """
    if not app_name:
        raise ValueError("app_name must not be empty")
    if not derived_data:
        raise ValueError("derived_data must not be empty")

    dd_path = Path(derived_data)

    # DerivedData copies
    if dd_path.exists():
        for dd_dir in dd_path.glob(f"{app_name}-*/Build/Products/*/{app_name}.app"):
            if dd_dir.is_dir():
                run([LSREGISTER, "-u", str(dd_dir)],
                    on_error="warn", label="deregister DD")

    # Trash copies
    trash = Path.home() / ".Trash"
    if trash.exists():
        for trash_app in trash.glob(f"{app_name}*.app"):
            if trash_app.is_dir():
                run([LSREGISTER, "-u", str(trash_app)],
                    on_error="warn", label="deregister Trash")


def register_app(app_path: str) -> None:
    """Register an app with LaunchServices (force)."""
    run([LSREGISTER, "-f", app_path], label="register app")


def dump_widget_registration(widget_id: str) -> str | None:
    """Query LaunchServices for a widget extension's registered path.

    Returns the path line, or None if not found.
    """
    result = run([LSREGISTER, "-dump"], on_error="warn", label="lsregister dump")
    lines = result.stdout.splitlines()
    for i, line in enumerate(lines):
        if f"plugin Identifiers:         {widget_id}" in line:
            # lsregister entries are separated by "----" lines.
            # Search backwards for "path:" within the same entry.
            for j in range(i - 1, -1, -1):
                if lines[j].startswith("path:"):
                    return lines[j]
                if "----" in lines[j]:
                    break  # Hit entry boundary — stop
            print(f"WARNING: Widget {widget_id} found at line {i} "
                  f"but no path line in same entry")
            return None
    return None
