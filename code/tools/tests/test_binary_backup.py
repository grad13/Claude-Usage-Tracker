"""Tests for binary backup logic in build-and-install.sh.

Covers:
  Test 6: Version-tagged rename backup (.app → .app.v0.9.1)
  Test 7: Missing Info.plist → .app.vunknown fallback
  Test 8: Same-version overwrite (existing backup replaced)
"""

import shutil
import subprocess

import pytest


def _has_plistbuddy():
    """Check if PlistBuddy is available (macOS only)."""
    return shutil.which("/usr/libexec/PlistBuddy") is not None


def _create_app_with_version(install_dir, app_name, version=None):
    """Create an .app directory with optional Info.plist version."""
    app_dir = install_dir / f"{app_name}.app" / "Contents"
    app_dir.mkdir(parents=True)

    if version is not None:
        plist = app_dir / "Info.plist"
        subprocess.run(
            [
                "/usr/libexec/PlistBuddy",
                "-c",
                f"Add :CFBundleShortVersionString string {version}",
                str(plist),
            ],
            check=True,
        )

    return install_dir / f"{app_name}.app"


def _run_backup_logic(install_dir, app_name):
    """Run the same backup logic as build-and-install.sh L99-111."""
    script = f"""
        APP_DIR="{install_dir}/{app_name}.app"
        if [ -d "$APP_DIR" ]; then
            PLIST="$APP_DIR/Contents/Info.plist"
            if [ -f "$PLIST" ]; then
                CV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
                    "$PLIST" 2>/dev/null || echo "unknown")
            else
                CV="unknown"
            fi
            BA="{install_dir}/{app_name}.app.v${{CV}}"
            rm -rf "$BA"
            mv "$APP_DIR" "$BA"
        fi
    """
    subprocess.run(["bash", "-c", script], check=True)


@pytest.mark.skipif(not _has_plistbuddy(), reason="PlistBuddy not available")
@pytest.mark.parametrize(
    "scenario,version,marker_before,expected_suffix,expected_marker",
    [
        # Test 6: versioned rename
        ("versioned", "0.9.1", None, "v0.9.1", None),
        # Test 7: no Info.plist → vunknown
        ("no_plist", None, None, "vunknown", None),
        # Test 8: same-version overwrite
        ("overwrite", "0.9.1", "old", "v0.9.1", "new"),
    ],
    ids=["versioned", "no_plist", "overwrite"],
)
def test_binary_backup(
    tmp_path, scenario, version, marker_before, expected_suffix, expected_marker
):
    install_dir = tmp_path / "Applications"
    install_dir.mkdir()

    # For overwrite test: create pre-existing backup
    if marker_before is not None:
        existing_backup = install_dir / f"TestApp.app.v{expected_suffix}"
        existing_backup.mkdir(parents=True)
        (existing_backup / "marker").write_text(marker_before)

    # Create the app
    if version is not None:
        _create_app_with_version(install_dir, "TestApp", version)
    else:
        # No Info.plist (Test 7)
        (install_dir / "TestApp.app" / "Contents").mkdir(parents=True)

    # For overwrite test: add marker to the app being backed up
    if expected_marker is not None:
        (install_dir / "TestApp.app" / "marker").write_text(expected_marker)

    _run_backup_logic(install_dir, "TestApp")

    # Verify backup was created with correct suffix
    backup = install_dir / f"TestApp.app.{expected_suffix}"
    assert backup.is_dir(), f"Expected {backup.name} to exist"

    # Original app should be gone (mv)
    assert not (install_dir / "TestApp.app").exists()

    # For overwrite test: verify content was replaced
    if expected_marker is not None:
        assert (backup / "marker").read_text() == expected_marker
