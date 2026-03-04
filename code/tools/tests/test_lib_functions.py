"""Tests for shared lib functions extracted in Step 8.

Covers:
  - lib/version.sh: get_app_version
  - lib/launchservices.sh: deregister_stale_apps (smoke test)
"""

import shutil
import subprocess

import pytest


# ---------------------------------------------------------------------------
# lib/version.sh: get_app_version
# ---------------------------------------------------------------------------

def _has_plistbuddy():
    return shutil.which("/usr/libexec/PlistBuddy") is not None


@pytest.mark.skipif(not _has_plistbuddy(), reason="PlistBuddy not available")
@pytest.mark.parametrize(
    "version,expected",
    [
        ("1.2.3", "1.2.3"),
        (None, "unknown"),  # no Info.plist
    ],
    ids=["with_version", "no_plist"],
)
def test_get_app_version(tmp_path, script_dir, version, expected):
    app_dir = tmp_path / "TestApp.app" / "Contents"
    app_dir.mkdir(parents=True)

    if version is not None:
        subprocess.run(
            [
                "/usr/libexec/PlistBuddy",
                "-c",
                f"Add :CFBundleShortVersionString string {version}",
                str(app_dir / "Info.plist"),
            ],
            check=True,
        )

    lib_path = script_dir / "lib" / "version.sh"
    result = subprocess.run(
        [
            "bash",
            "-c",
            f'source "{lib_path}" && get_app_version "{tmp_path / "TestApp.app"}"',
        ],
        capture_output=True,
        text=True,
    )
    assert result.stdout.strip() == expected


# ---------------------------------------------------------------------------
# lib/launchservices.sh: deregister_stale_apps (smoke test)
# ---------------------------------------------------------------------------

def test_deregister_stale_apps_no_crash(tmp_path, script_dir):
    """deregister_stale_apps should not crash even with empty DERIVED_DATA."""
    lib_path = script_dir / "lib" / "launchservices.sh"
    result = subprocess.run(
        [
            "bash",
            "-c",
            f'source "{lib_path}" && '
            f'APP_NAME=TestApp DERIVED_DATA="{tmp_path}" deregister_stale_apps',
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
