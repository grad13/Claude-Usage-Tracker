#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageTracker"
SCHEME="ClaudeUsageTracker"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
INSTALL_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

# Find DerivedData directory for this project
DD_DIR=$(find "$DERIVED_DATA" -maxdepth 1 -name "${APP_NAME}-*" -type d | head -1)
if [ -z "$DD_DIR" ]; then
    echo "DerivedData not found. Building fresh..."
fi

# --- データ保護: デプロイ前にバックアップを作成 ---
APPGROUP_DIR="$HOME/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker"
APPGROUP_DB="$APPGROUP_DIR/usage.db"
BACKUP_DIR="$APPGROUP_DIR/backups"
PRE_COUNT=0
if [ -f "$APPGROUP_DB" ]; then
    PRE_COUNT=$(sqlite3 -readonly "$APPGROUP_DB" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo 0)
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/usage_$(date +%Y%m%d_%H%M%S).db"
    cp "$APPGROUP_DB" "$BACKUP_FILE"
    echo "==> DB backup: $PRE_COUNT rows → $BACKUP_FILE"
    # 古いバックアップは10個まで保持
    ls -t "$BACKUP_DIR"/usage_*.db 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
fi

# Migrate data BEFORE tests (test host process can pollute App Group)
echo "==> Pre-test migration..."
"$SCRIPT_DIR/migrate-to-appgroup.sh"

# Snapshot settings BEFORE tests
APPGROUP_SETTINGS="$APPGROUP_DIR/settings.json"
SETTINGS_HASH_BEFORE=""
if [ -f "$APPGROUP_SETTINGS" ]; then
    SETTINGS_HASH_BEFORE=$(shasum -a 256 "$APPGROUP_SETTINGS" | cut -d' ' -f1)
    cp "$APPGROUP_SETTINGS" "${APPGROUP_SETTINGS}.backup"
fi

# Test gate: run unit tests before building
echo "==> Running unit tests..."
TEST_OUTPUT=$(xcodebuild -project "$PROJECT_DIR/code/ClaudeUsageTracker.xcodeproj" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    DEVELOPMENT_TEAM=C3WA2TT222 \
    -allowProvisioningUpdates \
    test 2>&1) || TEST_EXIT=$?
TEST_EXIT=${TEST_EXIT:-0}
echo "$TEST_OUTPUT" | tail -5
if [ $TEST_EXIT -ne 0 ]; then
    echo "ERROR: Unit tests failed. Aborting deployment."
    exit 1
fi

# Verify settings were NOT corrupted by test host
if [ -n "$SETTINGS_HASH_BEFORE" ] && [ -f "$APPGROUP_SETTINGS" ]; then
    SETTINGS_HASH_AFTER=$(shasum -a 256 "$APPGROUP_SETTINGS" | cut -d' ' -f1)
    if [ "$SETTINGS_HASH_BEFORE" != "$SETTINGS_HASH_AFTER" ]; then
        echo "WARNING: Tests corrupted settings.json — restoring from backup."
        cp "${APPGROUP_SETTINGS}.backup" "$APPGROUP_SETTINGS"
    fi
    rm -f "${APPGROUP_SETTINGS}.backup"
fi

# Deregister DerivedData app from LaunchServices (xcodebuild test registers it,
# which causes chronod to launch the widget extension from DerivedData instead of /Applications)
echo "==> Deregistering DerivedData from LaunchServices..."
for dd in "$DERIVED_DATA"/${APP_NAME}-*/Build/Products/*/${APP_NAME}.app; do
    [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
done
# 旧名の DerivedData もクリーンアップ
for dd in "$DERIVED_DATA"/WeatherCC-*/Build/Products/*/WeatherCC.app; do
    [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
done

# Test gate: run migration tests
echo "==> Running migration tests..."
"$SCRIPT_DIR/test-migration.sh"

# Build
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

# Gracefully quit running instance (gives WebKit time to flush cookies)
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 2
# Force kill if still running
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Copy to /Applications
echo "==> Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/${APP_NAME}.app"
cp -R "$BUILD_APP" "$INSTALL_DIR/${APP_NAME}.app"
rm -rf "$INSTALL_DIR/${APP_NAME}.app/Contents/PlugIns/ClaudeUsageTrackerTests.xctest"

# Verify widget extension exists before registration
WIDGET_APPEX="$INSTALL_DIR/${APP_NAME}.app/Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
if [ ! -d "$WIDGET_APPEX" ]; then
    echo "ERROR: Widget extension not found at $WIDGET_APPEX"
    echo "       PlugIns contents:"
    ls -la "$INSTALL_DIR/${APP_NAME}.app/Contents/PlugIns/" 2>/dev/null || echo "       (no PlugIns directory)"
    exit 1
fi
echo "==> Widget extension verified: $(basename "$WIDGET_APPEX")"

# Deregister ALL stale copies (DerivedData, Trash) so chronod only sees /Applications
echo "==> Cleaning stale LaunchServices registrations..."
for dd in "$DERIVED_DATA"/${APP_NAME}-*/Build/Products/*/${APP_NAME}.app; do
    [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
done
# 旧名もクリーンアップ
for dd in "$DERIVED_DATA"/WeatherCC-*/Build/Products/*/WeatherCC.app; do
    [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
done
for trash in "$HOME/.Trash/${APP_NAME}"*.app "$HOME/.Trash/WeatherCC"*.app; do
    [ -d "$trash" ] && "$LSREGISTER" -u "$trash" 2>/dev/null || true
done

# Register with LaunchServices, activate widget extension, restart chronod
echo "==> Registering /Applications/${APP_NAME}.app with LaunchServices..."
"$LSREGISTER" -f "$INSTALL_DIR/${APP_NAME}.app"
pluginkit -e use -i grad13.claudeusagetracker.widget 2>/dev/null || true
killall chronod 2>/dev/null || true
sleep 3

# Verify widget extension is registered from /Applications (not DerivedData)
echo "==> Verifying widget extension registration..."
WIDGET_REG=$("$LSREGISTER" -dump 2>/dev/null | grep -B80 "plugin Identifiers:         grad13.claudeusagetracker.widget" | grep "^path:" | head -1 || true)
if echo "$WIDGET_REG" | grep -q "DerivedData"; then
    echo "ERROR: Widget extension is still registered from DerivedData!"
    echo "       $WIDGET_REG"
    echo "       chronod will fail to launch the widget from /Applications."
    exit 1
fi
if echo "$WIDGET_REG" | grep -q "/Applications/"; then
    echo "==> Widget registered correctly: $WIDGET_REG"
else
    echo "WARNING: Could not verify widget registration path: $WIDGET_REG"
fi

# Migrate data to App Group (outside sandbox, before app launch)
echo "==> Migrating data to App Group..."
"$SCRIPT_DIR/migrate-to-appgroup.sh"

# データ整合性チェック（情報表示のみ、バックアップは手動復旧用に保持）
if [ -f "$APPGROUP_DB" ]; then
    POST_COUNT=$(sqlite3 -readonly "$APPGROUP_DB" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo 0)
    echo "==> Data integrity: before=$PRE_COUNT after=$POST_COUNT (backup: ${BACKUP_FILE:-none})"
fi

# Launch
echo "==> Launching..."
open "$INSTALL_DIR/${APP_NAME}.app"

echo "==> Done."
