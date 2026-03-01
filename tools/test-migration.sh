#!/bin/bash
# migrate-to-appgroup.sh の自動テスト
# ユーザー可変状態（settings.json, usage.db）がデプロイで破壊されないことを検証する
#
# テストケース:
#   1. App Group に settings.json がある場合 → 上書きされない
#   2. App Group に settings.json がない場合 → レガシーから移行される
#   3. App Group に usage.db がある場合 → 行数が減らない
#   4. レガシーに何もない場合 → エラーにならない
#
# 使い方: ./tools/test-migration.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATE="$SCRIPT_DIR/migrate-to-appgroup.sh"
TMPDIR_BASE=$(mktemp -d)
PASSED=0
FAILED=0
ERRORS=""

cleanup() {
  rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# テスト用に環境変数 HOME を差し替えて migration を実行する
run_migrate() {
  local fake_home="$1"
  HOME="$fake_home" bash "$MIGRATE" 2>&1
}

setup_appgroup_dir() {
  local fake_home="$1"
  mkdir -p "$fake_home/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker"
}

setup_sandbox_dir() {
  local fake_home="$1"
  mkdir -p "$fake_home/Library/Containers/grad13.weathercc.app/Data/Library/Application Support/WeatherCC"
}

setup_nonsandbox_dir() {
  local fake_home="$1"
  mkdir -p "$fake_home/Library/Application Support/WeatherCC"
}

appgroup_settings() {
  echo "$1/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker/settings.json"
}

sandbox_settings() {
  echo "$1/Library/Containers/grad13.weathercc.app/Data/Library/Application Support/WeatherCC/settings.json"
}

nonsandbox_settings() {
  echo "$1/Library/Application Support/WeatherCC/settings.json"
}

appgroup_db() {
  echo "$1/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker/usage.db"
}

sandbox_db() {
  echo "$1/Library/Containers/grad13.weathercc.app/Data/Library/Application Support/WeatherCC/usage.db"
}

setup_old_appgroup_dir() {
  local fake_home="$1"
  mkdir -p "$fake_home/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC"
}

old_appgroup_db() {
  echo "$1/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC/usage.db"
}

old_appgroup_tokens() {
  echo "$1/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC/tokens.db"
}

old_appgroup_snapshot() {
  echo "$1/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC/snapshot.db"
}

appgroup_tokens() {
  echo "$1/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker/tokens.db"
}

appgroup_snapshot() {
  echo "$1/Library/Group Containers/group.grad13.claudeusagetracker/Library/Application Support/ClaudeUsageTracker/snapshot.db"
}

old_appgroup_settings() {
  echo "$1/Library/Group Containers/C3WA2TT222.grad13.weathercc/Library/Application Support/WeatherCC/settings.json"
}

create_settings() {
  local path="$1"
  local interval="$2"
  cat > "$path" <<JSON
{
  "refresh_interval_minutes": $interval,
  "start_at_login": false
}
JSON
}

create_usage_db() {
  local path="$1"
  local rows="$2"
  sqlite3 "$path" "CREATE TABLE IF NOT EXISTS hourly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);"
  sqlite3 "$path" "CREATE TABLE IF NOT EXISTS weekly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);"
  sqlite3 "$path" "CREATE TABLE IF NOT EXISTS usage_log (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, hourly_percent REAL, weekly_percent REAL, hourly_session_id INTEGER REFERENCES hourly_sessions(id), weekly_session_id INTEGER REFERENCES weekly_sessions(id), CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL));"
  for i in $(seq 1 "$rows"); do
    sqlite3 "$path" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES ($((1740000000 + i)), $((i * 10)));"
  done
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASSED=$((PASSED + 1))
    echo "  PASS: $desc"
  else
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  FAIL: $desc (expected=$expected, actual=$actual)"
    echo "  FAIL: $desc (expected=$expected, actual=$actual)"
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    PASSED=$((PASSED + 1))
    echo "  PASS: $desc"
  else
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  FAIL: $desc (file not found: $path)"
    echo "  FAIL: $desc (file not found: $path)"
  fi
}

echo "=== migrate-to-appgroup.sh テスト ==="
echo ""

# --- Test 1: App Group に settings がある場合、上書きされない ---
echo "--- Test 1: 既存 settings.json は上書きされない ---"
T1="$TMPDIR_BASE/t1"
mkdir -p "$T1"
setup_appgroup_dir "$T1"
setup_sandbox_dir "$T1"

create_settings "$(appgroup_settings "$T1")" 1
create_settings "$(sandbox_settings "$T1")" 20

run_migrate "$T1" > /dev/null

actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T1")'))['refresh_interval_minutes'])")
assert_eq "App Group の refresh_interval_minutes が 1 のまま" "1" "$actual_interval"

echo ""

# --- Test 2: App Group に settings がない場合、レガシーから移行 ---
echo "--- Test 2: App Group に settings がなければレガシーから移行 ---"
T2="$TMPDIR_BASE/t2"
mkdir -p "$T2"
setup_appgroup_dir "$T2"
setup_sandbox_dir "$T2"

create_settings "$(sandbox_settings "$T2")" 10

run_migrate "$T2" > /dev/null

assert_file_exists "App Group に settings.json が作成される" "$(appgroup_settings "$T2")"
actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T2")'))['refresh_interval_minutes'])")
assert_eq "移行された refresh_interval_minutes が 10" "10" "$actual_interval"

echo ""

# --- Test 3: App Group の usage.db の行数が減らない ---
echo "--- Test 3: usage.db の行数が減らない ---"
T3="$TMPDIR_BASE/t3"
mkdir -p "$T3"
setup_appgroup_dir "$T3"
setup_sandbox_dir "$T3"

create_usage_db "$(appgroup_db "$T3")" 5
create_usage_db "$(sandbox_db "$T3")" 3

run_migrate "$T3" > /dev/null

actual_rows=$(sqlite3 "$(appgroup_db "$T3")" "SELECT COUNT(*) FROM usage_log;")
assert_eq "App Group DB の行数が 5 以上" "1" "$([ "$actual_rows" -ge 5 ] && echo 1 || echo 0)"

echo ""

# --- Test 4: レガシーに何もない場合、エラーにならない ---
echo "--- Test 4: レガシーが空でもエラーにならない ---"
T4="$TMPDIR_BASE/t4"
mkdir -p "$T4"
setup_appgroup_dir "$T4"

create_settings "$(appgroup_settings "$T4")" 3

output=$(run_migrate "$T4" 2>&1)
exit_code=$?
assert_eq "終了コードが 0" "0" "$exit_code"

actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T4")'))['refresh_interval_minutes'])")
assert_eq "settings が変わっていない" "3" "$actual_interval"

echo ""

# --- Test 5: nonsandbox のレガシーからも移行できる ---
echo "--- Test 5: nonsandbox レガシーから移行 ---"
T5="$TMPDIR_BASE/t5"
mkdir -p "$T5"
setup_appgroup_dir "$T5"
setup_nonsandbox_dir "$T5"

create_settings "$(nonsandbox_settings "$T5")" 7

run_migrate "$T5" > /dev/null

assert_file_exists "App Group に settings.json が作成される" "$(appgroup_settings "$T5")"
actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T5")'))['refresh_interval_minutes'])")
assert_eq "移行された refresh_interval_minutes が 7" "7" "$actual_interval"

echo ""

# --- Test 6: App Group settings + sandbox settings（sandbox の方が新しい mtime）→ 上書きされない（リグレッション防止） ---
echo "--- Test 6: sandbox が新しい mtime でも App Group settings は上書きされない ---"
T6="$TMPDIR_BASE/t6"
mkdir -p "$T6"
setup_appgroup_dir "$T6"
setup_sandbox_dir "$T6"

create_settings "$(appgroup_settings "$T6")" 1
sleep 1
create_settings "$(sandbox_settings "$T6")" 20

run_migrate "$T6" > /dev/null

actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T6")'))['refresh_interval_minutes'])")
assert_eq "App Group の refresh_interval_minutes が 1 のまま（mtime に関係なく）" "1" "$actual_interval"

echo ""

# --- Test 7: App Group DB + legacy DB（legacy の方が行数が少ない）→ App Group DB が変わらない ---
echo "--- Test 7: legacy DB の行数が少ない場合、App Group DB は変わらない ---"
T7="$TMPDIR_BASE/t7"
mkdir -p "$T7"
setup_appgroup_dir "$T7"
setup_sandbox_dir "$T7"

create_usage_db "$(appgroup_db "$T7")" 8
create_usage_db "$(sandbox_db "$T7")" 2

run_migrate "$T7" > /dev/null

actual_rows=$(sqlite3 "$(appgroup_db "$T7")" "SELECT COUNT(*) FROM usage_log;")
assert_eq "App Group DB の行数が 8 のまま" "8" "$actual_rows"

echo ""

# --- Test 8: 2回連続で migrate 実行 → 冪等性 ---
echo "--- Test 8: 2回連続で migrate しても結果が変わらない（冪等性） ---"
T8="$TMPDIR_BASE/t8"
mkdir -p "$T8"
setup_appgroup_dir "$T8"
setup_sandbox_dir "$T8"

create_settings "$(appgroup_settings "$T8")" 5
create_usage_db "$(appgroup_db "$T8")" 4
create_settings "$(sandbox_settings "$T8")" 15
create_usage_db "$(sandbox_db "$T8")" 2

run_migrate "$T8" > /dev/null
run_migrate "$T8" > /dev/null

actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T8")'))['refresh_interval_minutes'])")
actual_rows=$(sqlite3 "$(appgroup_db "$T8")" "SELECT COUNT(*) FROM usage_log;")
assert_eq "2回目以降も settings が 5 のまま" "5" "$actual_interval"
assert_eq "2回目以降も DB 行数が 4 のまま" "4" "$actual_rows"

echo ""

# --- Test 9: テスト DB のスキーマが実アプリのスキーマと一致する ---
echo "--- Test 9: create_usage_db() のスキーマが期待カラムと一致 ---"
T9="$TMPDIR_BASE/t9"
mkdir -p "$T9"
T9_DB="$T9/verify.db"

create_usage_db "$T9_DB" 0

# usage_log のカラム名を取得（PRAGMA table_info の name 列 = 2番目）
actual_cols=$(sqlite3 "$T9_DB" "PRAGMA table_info(usage_log);" | cut -d'|' -f2 | sort | tr '\n' ',')
expected_cols="hourly_percent,hourly_session_id,id,timestamp,weekly_percent,weekly_session_id,"
assert_eq "usage_log カラムが期待通り" "$expected_cols" "$actual_cols"

# hourly_sessions テーブルの存在確認
hs_exists=$(sqlite3 "$T9_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='hourly_sessions';")
assert_eq "hourly_sessions テーブルが存在する" "1" "$hs_exists"

# weekly_sessions テーブルの存在確認
ws_exists=$(sqlite3 "$T9_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='weekly_sessions';")
assert_eq "weekly_sessions テーブルが存在する" "1" "$ws_exists"

echo ""

# --- Test 10: tokens.db が旧 App Group から新 App Group に移行される ---
echo "--- Test 10: tokens.db が旧 App Group から新に移行される ---"
T10="$TMPDIR_BASE/t10"
mkdir -p "$T10"
setup_appgroup_dir "$T10"
setup_old_appgroup_dir "$T10"

echo "dummy" > "$(old_appgroup_tokens "$T10")"

run_migrate "$T10" > /dev/null

assert_file_exists "tokens.db が新 App Group に移行される" "$(appgroup_tokens "$T10")"

echo ""

# --- Test 11: snapshot.db が旧 App Group から新 App Group に移行される ---
echo "--- Test 11: snapshot.db が旧 App Group から新に移行される ---"
T11="$TMPDIR_BASE/t11"
mkdir -p "$T11"
setup_appgroup_dir "$T11"
setup_old_appgroup_dir "$T11"

echo "dummy" > "$(old_appgroup_snapshot "$T11")"

run_migrate "$T11" > /dev/null

assert_file_exists "snapshot.db が新 App Group に移行される" "$(appgroup_snapshot "$T11")"

echo ""

# --- Test 12: usage.db が旧 App Group をレガシーソースとしてマージされる ---
echo "--- Test 12: usage.db が旧 App Group からマージされる ---"
T12="$TMPDIR_BASE/t12"
mkdir -p "$T12"
setup_appgroup_dir "$T12"
setup_old_appgroup_dir "$T12"

create_usage_db "$(old_appgroup_db "$T12")" 6

run_migrate "$T12" > /dev/null

actual_rows=$(sqlite3 "$(appgroup_db "$T12")" "SELECT COUNT(*) FROM usage_log;")
assert_eq "旧 App Group の usage.db がマージされた" "6" "$actual_rows"

echo ""

# --- Test 13: 旧 App Group から settings.json が移行される ---
echo "--- Test 13: 旧 App Group から settings.json が移行される ---"
T13="$TMPDIR_BASE/t13"
mkdir -p "$T13"
setup_appgroup_dir "$T13"
setup_old_appgroup_dir "$T13"

create_settings "$(old_appgroup_settings "$T13")" 42

run_migrate "$T13" > /dev/null

assert_file_exists "App Group に settings.json が作成される" "$(appgroup_settings "$T13")"
actual_interval=$(python3 -c "import json; print(json.load(open('$(appgroup_settings "$T13")'))['refresh_interval_minutes'])")
assert_eq "旧 App Group から移行された refresh_interval_minutes が 42" "42" "$actual_interval"

echo ""

# --- Summary ---
echo "=== 結果: $PASSED passed, $FAILED failed ==="
if [ "$FAILED" -gt 0 ]; then
  echo -e "\n失敗したテスト:$ERRORS"
  exit 1
fi
