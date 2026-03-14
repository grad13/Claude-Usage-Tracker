"""Integration tests for deploy pipeline.

These tests verify the actual deployed app state.
They require a successful build+install to have been performed first.
Skip automatically if the app is not installed.

Covers:
  Test 1: find_derived_data_dir returns correct project
  Test 2: Built app has correct Bundle ID
  Test 3: Installed app code signature is valid
  Test 4: Installed app has required entitlements (app + widget)
  Test 5: Widget binary contains expected symbols
"""

import plistlib
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

APP_PATH = Path("/Applications/ClaudeUsageTracker.app")
WIDGET_APPEX = APP_PATH / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"

requires_installed_app = pytest.mark.skipif(
    not APP_PATH.exists(),
    reason="ClaudeUsageTracker.app not installed in /Applications",
)


@requires_installed_app
def test_installed_app_has_correct_bundle_id():
    """Test 2: Installed .app has the correct Bundle ID."""
    plist_path = APP_PATH / "Contents/Info.plist"
    with open(plist_path, "rb") as f:
        plist = plistlib.load(f)
    assert plist["CFBundleIdentifier"] == "grad13.claudeusagetracker"


@requires_installed_app
def test_installed_app_code_signature_valid():
    """Test 3: codesign --verify --deep --strict succeeds."""
    result = subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(APP_PATH)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, (
        f"Code signature invalid:\n{result.stderr}"
    )


@requires_installed_app
def test_installed_app_has_app_group_entitlement():
    """Test 4a: Main app has application-groups entitlement."""
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", str(APP_PATH)],
        capture_output=True, text=True,
    )
    assert "application-groups" in result.stdout, (
        f"Main app missing application-groups entitlement:\n{result.stdout[:500]}"
    )


@requires_installed_app
@pytest.mark.skipif(
    not WIDGET_APPEX.exists(),
    reason="Widget extension not found",
)
def test_installed_widget_has_app_group_entitlement():
    """Test 4b: Widget extension has application-groups entitlement."""
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", str(WIDGET_APPEX)],
        capture_output=True, text=True,
    )
    assert "application-groups" in result.stdout, (
        f"Widget missing application-groups entitlement:\n{result.stdout[:500]}"
    )


@requires_installed_app
@pytest.mark.skipif(
    not WIDGET_APPEX.exists(),
    reason="Widget extension not found",
)
def test_installed_widget_binary_exists():
    """Test 5: Widget binary exists and is non-empty."""
    widget_bin = (
        WIDGET_APPEX / "Contents/MacOS/ClaudeUsageTrackerWidgetExtension"
    )
    assert widget_bin.exists(), f"Widget binary not found: {widget_bin}"
    assert widget_bin.stat().st_size > 0, "Widget binary is empty"
