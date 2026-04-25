# meta: updated=2026-04-25 14:55 checked=-
"""LaunchServices utilities for app registration management."""
from __future__ import annotations

import re
from pathlib import Path

from runner import run

LSREGISTER = (
    "/System/Library/Frameworks/CoreServices.framework"
    "/Versions/Current/Frameworks/LaunchServices.framework"
    "/Versions/Current/Support/lsregister"
)


def unregister_path(path: str) -> None:
    """Thin wrapper for `lsregister -u`. Idempotent — failures are warned."""
    run([LSREGISTER, "-u", path], on_error="warn", label="lsregister -u")


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


def cleanup_stale_lsregister(app_name: str, install_dir: Path) -> int:
    """Deregister every `.app` / `.appex` for `app_name` whose path does NOT
    start with `install_dir`. Catches DerivedData, build/, xcarchive/, export/
    and any other ghost path that may have been registered.

    Returns the number of paths unregistered. Idempotent.
    """
    result = run([LSREGISTER, "-dump"], on_error="warn", label="lsregister -dump")
    install_prefix = f"{install_dir}/{app_name}.app"

    # Match `path:` lines that contain `{app_name}.app` (covers both .app and
    # .app/Contents/PlugIns/*.appex).
    paths: list[str] = []
    for line in result.stdout.splitlines():
        m = re.match(r"^path:\s+(.+?)(?:\s+\(0x[0-9a-fA-F]+\))?\s*$", line)
        if not m:
            continue
        path = m.group(1)
        if f"/{app_name}.app" not in path:
            continue
        if path.startswith(install_prefix):
            continue
        paths.append(path)

    # Sort so .appex comes before .app (deregistering parent first leaves the
    # plugin dangling, so do plugins first).
    paths.sort(key=lambda p: (".appex" not in p, p))

    for p in paths:
        unregister_path(p)

    return len(paths)


def widget_running_path(widget_extension_name: str) -> str | None:
    """Return the absolute path of the running widget extension process, or
    None if no process matches. Uses `pgrep -f` + `ps` (no AppleScript).
    """
    pgrep = run(["pgrep", "-f", widget_extension_name],
                on_error="warn", label=f"pgrep {widget_extension_name}")
    pids = [p.strip() for p in pgrep.stdout.splitlines() if p.strip()]
    if not pids:
        return None
    # The widget extension process command line includes the absolute path.
    ps = run(["ps", "-p", pids[0], "-o", "command="],
             on_error="warn", label=f"ps {pids[0]}")
    cmd = ps.stdout.strip()
    if not cmd:
        return None
    # Command line is `<abs_path> -LaunchArguments ...`. First token is the path.
    return cmd.split(" ", 1)[0]


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
