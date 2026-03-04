#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-ClaudeUsageTracker}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Available versions:"
    ls -d "$INSTALL_DIR/${APP_NAME}.app.v"* 2>/dev/null | while read d; do
        v=$(basename "$d" | sed "s/${APP_NAME}.app.//")
        echo "  $v"
    done
    echo ""
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.9.1"
    exit 1
fi

BACKUP_APP="$INSTALL_DIR/${APP_NAME}.app.${VERSION}"
if [ ! -d "$BACKUP_APP" ]; then
    echo "ERROR: $BACKUP_APP not found"
    exit 1
fi

# /Applications 書き込み権限確認
if ! touch "$INSTALL_DIR/.rollback_test" 2>/dev/null; then
    echo "ERROR: Cannot write to $INSTALL_DIR — run with sudo or check permissions"
    exit 1
fi
rm -f "$INSTALL_DIR/.rollback_test"

# テストモードではアプリ操作をスキップ
if [ -z "${ROLLBACK_TEST_MODE:-}" ]; then
    echo "==> Quitting $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 2
    killall "$APP_NAME" 2>/dev/null || true
    sleep 0.5
fi

echo "==> Restoring $VERSION..."
rm -rf "$INSTALL_DIR/${APP_NAME}.app"
cp -R "$BACKUP_APP" "$INSTALL_DIR/${APP_NAME}.app"

if [ -z "${ROLLBACK_TEST_MODE:-}" ]; then
    echo "==> Registering with LaunchServices..."
    "$LSREGISTER" -f "$INSTALL_DIR/${APP_NAME}.app"

    echo "==> Launching..."
    open "$INSTALL_DIR/${APP_NAME}.app"
fi

echo "==> Rollback to $VERSION complete."
echo "    Data (DB, Cookie) は変更されていません。"
