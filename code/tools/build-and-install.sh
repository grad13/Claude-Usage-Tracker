#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/data-protection.sh"
APP_NAME="ClaudeUsageTracker"
SCHEME="ClaudeUsageTracker"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
INSTALL_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
APPGROUP_DIR="$HOME/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker"
APPGROUP_DB="$APPGROUP_DIR/usage.db"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

backup_database() {
    local backup_dir="$APPGROUP_DIR/backups"
    PRE_COUNT=0
    BACKUP_FILE=""
    if [ -f "$APPGROUP_DB" ]; then
        PRE_COUNT=$(sqlite3 -readonly "$APPGROUP_DB" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo 0)
        mkdir -p "$backup_dir"
        BACKUP_FILE="$backup_dir/usage_$(date +%Y%m%d_%H%M%S).db"
        cp "$APPGROUP_DB" "$BACKUP_FILE"
        echo "==> DB backup: $PRE_COUNT rows → $BACKUP_FILE"
        # 古いバックアップは10個まで保持
        ls -t "$backup_dir"/usage_*.db 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    fi
}

snapshot_protected_files() {
    APPGROUP_SETTINGS="$APPGROUP_DIR/settings.json"
    COOKIE_FILE="$APPGROUP_DIR/session-cookies.json"
    snapshot_file "$APPGROUP_SETTINGS"
    snapshot_file "$COOKIE_FILE"
}

run_test_gate() {
    echo "==> Running unit tests..."
    local test_exit=0
    local test_output
    test_output=$(xcodebuild -project "$PROJECT_DIR/code/ClaudeUsageTracker.xcodeproj" \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        DEVELOPMENT_TEAM=C3WA2TT222 \
        -allowProvisioningUpdates \
        test 2>&1) || test_exit=$?
    echo "$test_output" | tail -5
    if [ $test_exit -ne 0 ]; then
        echo "ERROR: Unit tests failed. Aborting deployment."
        exit 1
    fi

    # Verify settings and session cookies were NOT corrupted by test host
    restore_file_if_changed "$APPGROUP_SETTINGS" || true
    restore_file_if_changed "$COOKIE_FILE" || true
}

deregister_stale_apps() {
    # Deregister DerivedData and Trash copies so chronod only sees /Applications
    for dd in "$DERIVED_DATA"/${APP_NAME}-*/Build/Products/*/${APP_NAME}.app; do
        [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
    done
    # 旧名の DerivedData もクリーンアップ
    for dd in "$DERIVED_DATA"/WeatherCC-*/Build/Products/*/WeatherCC.app; do
        [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
    done
    for trash in "$HOME/.Trash/${APP_NAME}"*.app "$HOME/.Trash/WeatherCC"*.app; do
        [ -d "$trash" ] && "$LSREGISTER" -u "$trash" 2>/dev/null || true
    done
}

build_app() {
    echo "==> Building $SCHEME..."
    xcodebuild -project "$PROJECT_DIR/code/ClaudeUsageTracker.xcodeproj" \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -configuration Debug \
        DEVELOPMENT_TEAM=C3WA2TT222 \
        -allowProvisioningUpdates \
        build 2>&1 | tail -5

    # Re-resolve DerivedData after build
    DD_DIR=$(find "$DERIVED_DATA" -maxdepth 1 -name "${APP_NAME}-*" -type d | head -1)
    BUILD_APP="$DD_DIR/Build/Products/Debug/${APP_NAME}.app"

    if [ ! -d "$BUILD_APP" ]; then
        echo "ERROR: Built app not found at $BUILD_APP"
        exit 1
    fi
}

install_app() {
    # Gracefully quit running instance (gives WebKit time to flush cookies)
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    killall "$APP_NAME" 2>/dev/null || true
    sleep 0.5

    # Backup current app with version number
    echo "==> Installing to $INSTALL_DIR..."
    if [ -d "$INSTALL_DIR/${APP_NAME}.app" ]; then
        local plist="$INSTALL_DIR/${APP_NAME}.app/Contents/Info.plist"
        local current_version
        if [ -f "$plist" ]; then
            current_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
                "$plist" 2>/dev/null || echo "unknown")
        else
            current_version="unknown"
        fi
        local backup_app="$INSTALL_DIR/${APP_NAME}.app.v${current_version}"
        echo "==> Backing up current app as ${APP_NAME}.app.v${current_version}..."
        rm -rf "$backup_app"
        mv "$INSTALL_DIR/${APP_NAME}.app" "$backup_app"
    fi
    cp -R "$BUILD_APP" "$INSTALL_DIR/${APP_NAME}.app"
    rm -rf "$INSTALL_DIR/${APP_NAME}.app/Contents/PlugIns/ClaudeUsageTrackerTests.xctest"

    # Verify widget extension exists before registration
    local widget_appex="$INSTALL_DIR/${APP_NAME}.app/Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
    if [ ! -d "$widget_appex" ]; then
        echo "ERROR: Widget extension not found at $widget_appex"
        echo "       PlugIns contents:"
        ls -la "$INSTALL_DIR/${APP_NAME}.app/Contents/PlugIns/" 2>/dev/null || echo "       (no PlugIns directory)"
        exit 1
    fi
    echo "==> Widget extension verified: $(basename "$widget_appex")"
}

register_and_verify() {
    # Deregister stale copies before registering the new one
    echo "==> Cleaning stale LaunchServices registrations..."
    deregister_stale_apps

    # Register with LaunchServices, activate widget extension, restart chronod
    echo "==> Registering /Applications/${APP_NAME}.app with LaunchServices..."
    "$LSREGISTER" -f "$INSTALL_DIR/${APP_NAME}.app"
    pluginkit -e use -i grad13.claudeusagetracker.widget 2>/dev/null || true
    killall chronod 2>/dev/null || true
    sleep 3

    # Verify widget extension is registered from /Applications (not DerivedData)
    echo "==> Verifying widget extension registration..."
    local widget_reg
    widget_reg=$("$LSREGISTER" -dump 2>/dev/null | grep -B80 "plugin Identifiers:         grad13.claudeusagetracker.widget" | grep "^path:" | head -1 || true)
    if echo "$widget_reg" | grep -q "DerivedData"; then
        echo "ERROR: Widget extension is still registered from DerivedData!"
        echo "       $widget_reg"
        echo "       chronod will fail to launch the widget from /Applications."
        exit 1
    fi
    if echo "$widget_reg" | grep -q "/Applications/"; then
        echo "==> Widget registered correctly: $widget_reg"
    else
        echo "WARNING: Could not verify widget registration path: $widget_reg"
    fi

    # データ整合性チェック（検出 + abort、自動復元はしない）
    if [ -f "${BACKUP_FILE:-}" ] && [ -f "$APPGROUP_DB" ]; then
        local lost
        lost=$(sqlite3 "$APPGROUP_DB" "
            ATTACH '${BACKUP_FILE}' AS backup;
            SELECT COUNT(*) FROM backup.usage_log
            WHERE rowid NOT IN (SELECT rowid FROM main.usage_log);
        " 2>/dev/null || echo "-1")
        if [ "$lost" != "0" ]; then
            echo "FATAL: $lost rows lost during deploy!"
            echo "       Backup available: $BACKUP_FILE"
            echo "       To restore: cp \"$BACKUP_FILE\" \"$APPGROUP_DB\""
            echo "       Aborting launch. Investigate before restoring."
            exit 1
        else
            echo "==> Data integrity verified: no rows lost (backup: $BACKUP_FILE)"
        fi
    fi

    # Launch
    echo "==> Launching..."
    open "$INSTALL_DIR/${APP_NAME}.app"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Find DerivedData directory for this project
DD_DIR=$(find "$DERIVED_DATA" -maxdepth 1 -name "${APP_NAME}-*" -type d | head -1)
if [ -z "$DD_DIR" ]; then
    echo "DerivedData not found. Building fresh..."
fi

backup_database
snapshot_protected_files
run_test_gate

echo "==> Deregistering DerivedData from LaunchServices..."
deregister_stale_apps

build_app
install_app
register_and_verify

echo "==> Done."
