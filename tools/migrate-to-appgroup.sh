#!/bin/bash
# データを App Group コンテナに移行する
# sandbox 内のアプリからは ~/Library/Application Support/ にアクセスできないため、
# アプリ起動前にこのスクリプトで移行する。
#
# 使い方: ./tools/migrate-to-appgroup.sh

set -euo pipefail

APPGROUP="$HOME/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC"
NONSANDBOX="$HOME/Library/Application Support/WeatherCC"
SANDBOX="$HOME/Library/Containers/grad13.weathercc.app/Data/Library/Application Support/WeatherCC"

mkdir -p "$APPGROUP"

# --- usage.db 移行 ---
AG_DB="$APPGROUP/usage.db"
AG_COUNT=0
if [ -f "$AG_DB" ]; then
  AG_COUNT=$(sqlite3 "$AG_DB" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo 0)
fi

BEST_SOURCE=""
BEST_COUNT=0

for label_path in "sandbox:$SANDBOX" "nonsandbox:$NONSANDBOX"; do
  label="${label_path%%:*}"
  path="${label_path#*:}"
  db="$path/usage.db"
  if [ -f "$db" ]; then
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo 0)
    echo "  $label DB: $count rows"
    if [ "$count" -gt "$BEST_COUNT" ]; then
      BEST_COUNT=$count
      BEST_SOURCE="$db"
    fi
  fi
done

if [ "$AG_COUNT" -gt 0 ]; then
  # App Group DB にデータがある場合は絶対に上書きしない
  # レガシー DB にしかないデータがあれば INSERT で追加する
  if [ -n "$BEST_SOURCE" ] && [ "$BEST_COUNT" -gt 0 ]; then
    BEFORE=$AG_COUNT
    sqlite3 "$BEST_SOURCE" "ATTACH '${AG_DB}' AS ag;
      INSERT OR IGNORE INTO ag.usage_log(timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id)
      SELECT timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id
      FROM usage_log
      WHERE timestamp NOT IN (SELECT timestamp FROM ag.usage_log);"
    AFTER=$(sqlite3 "$AG_DB" "SELECT COUNT(*) FROM usage_log;" 2>/dev/null || echo 0)
    echo "  Merged legacy → App Group: $BEFORE → $AFTER rows (added $((AFTER - BEFORE)))"
  else
    echo "  DB migration not needed (App Group: $AG_COUNT rows, no legacy data)"
  fi
elif [ -n "$BEST_SOURCE" ] && [ "$BEST_COUNT" -gt 0 ]; then
  # App Group DB が空または存在しない場合のみコピーを許可
  echo "  Migrating DB: $BEST_SOURCE ($BEST_COUNT rows) → App Group (was empty)"
  cp -f "$BEST_SOURCE" "$AG_DB"
else
  echo "  DB migration not needed (no data anywhere)"
fi

# --- settings.json 移行 ---
AG_SETTINGS="$APPGROUP/settings.json"

if [ -f "$AG_SETTINGS" ]; then
  echo "  Settings already in App Group — skipping migration"
else
  # App Group に settings がない場合のみレガシーから移行
  for path in "$SANDBOX/settings.json" "$NONSANDBOX/settings.json"; do
    if [ -f "$path" ]; then
      echo "  Migrating settings: $path → App Group"
      cp -f "$path" "$AG_SETTINGS"
      break
    fi
  done
  if [ ! -f "$AG_SETTINGS" ]; then
    echo "  No legacy settings found"
  fi
fi

# --- legacy ディレクトリは削除しない（データ損失防止） ---
for path in "$SANDBOX" "$NONSANDBOX"; do
  if [ -d "$path" ]; then
    echo "  Legacy exists (kept): $path"
  fi
done

echo "  Migration complete."
