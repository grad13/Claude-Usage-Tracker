#!/bin/bash
# Step 3 リネームデプロイのロールバック
# E2E デプロイ (build-and-install.sh) が失敗した場合に実行する
#
# やること:
#   1. ClaudeUsageTracker を停止・削除
#   2. LaunchServices から deregister
#   3. 旧 App Group データが無傷であることを確認
#   4. WeatherCC.app が残っていることを確認
#
# やらないこと:
#   - git revert（手動で git checkout v0.8.1 する）
#   - 新 App Group のデータ削除（harm なし、放置可）
#   - 旧 App Group のデータ変更（コピー元なので変更されていない）
#
# 使い方: ./tools/rollback-rename.sh

set -euo pipefail

APP_NAME="ClaudeUsageTracker"
INSTALL_DIR="/Applications"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
OLD_APPGROUP="$HOME/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC"

echo "=== Step 3 ロールバック ==="

# 1. ClaudeUsageTracker を停止
echo "==> Stopping $APP_NAME..."
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
killall "$APP_NAME" 2>/dev/null || true

# 2. LaunchServices から deregister
echo "==> Deregistering from LaunchServices..."
if [ -d "$INSTALL_DIR/${APP_NAME}.app" ]; then
    "$LSREGISTER" -u "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true
fi
for dd in "$DERIVED_DATA"/${APP_NAME}-*/Build/Products/*/${APP_NAME}.app; do
    [ -d "$dd" ] && "$LSREGISTER" -u "$dd" 2>/dev/null || true
done

# 3. /Applications から削除
if [ -d "$INSTALL_DIR/${APP_NAME}.app" ]; then
    echo "==> Removing $INSTALL_DIR/${APP_NAME}.app..."
    rm -rf "$INSTALL_DIR/${APP_NAME}.app"
    echo "  Removed."
else
    echo "  $INSTALL_DIR/${APP_NAME}.app not found (nothing to remove)."
fi

# 4. 旧 App Group データの確認
echo "==> Verifying old App Group data..."
ERRORS=0

for file in usage.db tokens.db snapshot.db settings.json; do
    path="$OLD_APPGROUP/$file"
    if [ -f "$path" ]; then
        if [ "$file" = "usage.db" ]; then
            rows=$(sqlite3 -readonly "$path" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo "ERROR")
            echo "  OK: $file ($rows rows)"
        else
            size=$(stat -f%z "$path" 2>/dev/null || echo "?")
            echo "  OK: $file (${size} bytes)"
        fi
    else
        echo "  MISSING: $file"
        ERRORS=$((ERRORS + 1))
    fi
done

# 5. WeatherCC.app の確認
echo "==> Verifying WeatherCC.app..."
if [ -d "$INSTALL_DIR/WeatherCC.app" ]; then
    echo "  OK: $INSTALL_DIR/WeatherCC.app exists."
else
    echo "  WARNING: $INSTALL_DIR/WeatherCC.app not found!"
    ERRORS=$((ERRORS + 1))
fi

# 6. サマリー
echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== ロールバック完了 ==="
    echo "  WeatherCC.app はそのまま動作可能です。"
    echo "  git を戻すには: git checkout v0.8.1"
else
    echo "=== ロールバック完了（警告 ${ERRORS} 件） ==="
    echo "  上記の MISSING/WARNING を確認してください。"
fi
