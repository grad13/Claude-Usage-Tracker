#!/bin/bash
# データを App Group コンテナに移行する
# sandbox 内のアプリからは ~/Library/Application Support/ にアクセスできないため、
# アプリ起動前にこのスクリプトで移行する。
#
# 使い方: ./tools/migrate-to-appgroup.sh

set -euo pipefail

APPGROUP="$HOME/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker"
OLD_APPGROUP="$HOME/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC"
NONSANDBOX="$HOME/Library/Application Support/WeatherCC"
SANDBOX="$HOME/Library/Containers/grad13.weathercc.app/Data/Library/Application Support/WeatherCC"

mkdir -p "$APPGROUP"

# --- usage.db 移行（レガシーから常に上書きコピー） ---
AG_DB="$APPGROUP/usage.db"
for path in "$OLD_APPGROUP/usage.db" "$SANDBOX/usage.db" "$NONSANDBOX/usage.db"; do
  if [ -f "$path" ]; then
    echo "  Copying usage.db: $path → App Group"
    cp -f "$path" "$AG_DB"
    break
  fi
done

# --- settings.json 移行 ---
AG_SETTINGS="$APPGROUP/settings.json"

if [ -f "$AG_SETTINGS" ]; then
  echo "  Settings already in App Group — skipping migration"
else
  # App Group に settings がない場合のみレガシーから移行
  for path in "$OLD_APPGROUP/settings.json" "$SANDBOX/settings.json" "$NONSANDBOX/settings.json"; do
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

# --- tokens.db 移行（レガシーから常に上書きコピー） ---
AG_TOKENS="$APPGROUP/tokens.db"
for path in "$OLD_APPGROUP/tokens.db" "$SANDBOX/tokens.db" "$NONSANDBOX/tokens.db"; do
  if [ -f "$path" ]; then
    echo "  Copying tokens.db: $path → App Group"
    cp -f "$path" "$AG_TOKENS"
    break
  fi
done

# --- snapshot.db 移行（レガシーから常に上書きコピー） ---
AG_SNAPSHOT="$APPGROUP/snapshot.db"
for path in "$OLD_APPGROUP/snapshot.db" "$SANDBOX/snapshot.db" "$NONSANDBOX/snapshot.db"; do
  if [ -f "$path" ]; then
    echo "  Copying snapshot.db: $path → App Group"
    cp -f "$path" "$AG_SNAPSHOT"
    break
  fi
done

# --- legacy ディレクトリは削除しない（データ損失防止） ---
for path in "$OLD_APPGROUP" "$SANDBOX" "$NONSANDBOX"; do
  if [ -d "$path" ]; then
    echo "  Legacy exists (kept): $path"
  fi
done

echo "  Migration complete."
