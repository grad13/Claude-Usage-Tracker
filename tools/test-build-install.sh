#!/bin/bash
# build-and-install.sh のバックアップ復元ロジックの単体テスト
# テスト対象は build-and-install.sh から抽出した SQL ロジック（スクリプト全体の実行は不要）
#
# テストケース:
#   1. バックアップからの INSERT マージが正しく動作する
#   2. バックアップ DB が空の場合にエラーにならない
#   3. バックアップファイルローテーション（10個保持）
#
# 使い方: ./tools/test-build-install.sh

set -euo pipefail

TMPDIR_BASE=$(mktemp -d)
PASSED=0
FAILED=0
ERRORS=""

cleanup() {
  rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

create_usage_db() {
  local path="$1"
  sqlite3 "$path" "CREATE TABLE IF NOT EXISTS hourly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);"
  sqlite3 "$path" "CREATE TABLE IF NOT EXISTS weekly_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, resets_at INTEGER NOT NULL UNIQUE);"
  sqlite3 "$path" "CREATE TABLE IF NOT EXISTS usage_log (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, hourly_percent REAL, weekly_percent REAL, hourly_session_id INTEGER REFERENCES hourly_sessions(id), weekly_session_id INTEGER REFERENCES weekly_sessions(id), CHECK (hourly_percent IS NOT NULL OR weekly_percent IS NOT NULL));"
}

# build-and-install.sh L159-163 と同じマージ SQL
run_merge_sql() {
  local backup_db="$1"
  local current_db="$2"
  sqlite3 "$backup_db" "ATTACH '${current_db}' AS current;
    INSERT OR IGNORE INTO current.usage_log(timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id)
    SELECT timestamp, hourly_percent, weekly_percent, hourly_session_id, weekly_session_id
    FROM usage_log
    WHERE timestamp NOT IN (SELECT timestamp FROM current.usage_log);"
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

echo "=== build-and-install.sh バックアップ復元テスト ==="
echo ""

# --- Test 1: バックアップからの INSERT マージが正しく動作する ---
echo "--- Test 1: INSERT マージ（backup固有 + current固有 + 共通行） ---"
T1="$TMPDIR_BASE/t1"
mkdir -p "$T1"
BACKUP_DB="$T1/backup.db"
CURRENT_DB="$T1/current.db"

create_usage_db "$BACKUP_DB"
create_usage_db "$CURRENT_DB"

# backup: 3行（ts=1001, 1002, 1003）
sqlite3 "$BACKUP_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1001, 10.0);"
sqlite3 "$BACKUP_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1002, 20.0);"
sqlite3 "$BACKUP_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1003, 30.0);"

# current: 2行（ts=1002 は共通、ts=1004 は current 固有）
sqlite3 "$CURRENT_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1002, 20.0);"
sqlite3 "$CURRENT_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1004, 40.0);"

run_merge_sql "$BACKUP_DB" "$CURRENT_DB"

actual_rows=$(sqlite3 "$CURRENT_DB" "SELECT COUNT(*) FROM usage_log;")
assert_eq "マージ後の合計行数が 4（backup固有2 + 共通1 + current固有1）" "4" "$actual_rows"

# backup 固有データが current にマージされていること
backup_only_1=$(sqlite3 "$CURRENT_DB" "SELECT hourly_percent FROM usage_log WHERE timestamp=1001;")
assert_eq "backup 固有行（ts=1001）がマージされている" "10.0" "$backup_only_1"

backup_only_2=$(sqlite3 "$CURRENT_DB" "SELECT hourly_percent FROM usage_log WHERE timestamp=1003;")
assert_eq "backup 固有行（ts=1003）がマージされている" "30.0" "$backup_only_2"

# current 固有データが残っていること
current_only=$(sqlite3 "$CURRENT_DB" "SELECT hourly_percent FROM usage_log WHERE timestamp=1004;")
assert_eq "current 固有行（ts=1004）が保持されている" "40.0" "$current_only"

# 共通行が重複していないこと
dup_count=$(sqlite3 "$CURRENT_DB" "SELECT COUNT(*) FROM usage_log WHERE timestamp=1002;")
assert_eq "共通行（ts=1002）が重複していない" "1" "$dup_count"

echo ""

# --- Test 2: バックアップ DB が空の場合にエラーにならない ---
echo "--- Test 2: 空 backup でエラーにならない ---"
T2="$TMPDIR_BASE/t2"
mkdir -p "$T2"
BACKUP_DB_2="$T2/backup.db"
CURRENT_DB_2="$T2/current.db"

create_usage_db "$BACKUP_DB_2"
create_usage_db "$CURRENT_DB_2"

# current: 3行
sqlite3 "$CURRENT_DB_2" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (2001, 50.0);"
sqlite3 "$CURRENT_DB_2" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (2002, 60.0);"
sqlite3 "$CURRENT_DB_2" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (2003, 70.0);"

# backup: 0行（空）
run_merge_sql "$BACKUP_DB_2" "$CURRENT_DB_2"
exit_code=$?
assert_eq "空 backup でのマージが正常終了（exit code 0）" "0" "$exit_code"

actual_rows=$(sqlite3 "$CURRENT_DB_2" "SELECT COUNT(*) FROM usage_log;")
assert_eq "current の行数が 3 のまま" "3" "$actual_rows"

echo ""

# --- Test 3: バックアップファイルローテーション（10個保持） ---
echo "--- Test 3: バックアップローテーション（12→10、古い2個削除） ---"
T3="$TMPDIR_BASE/t3"
BACKUP_DIR="$T3/backups"
mkdir -p "$BACKUP_DIR"

# 12個のバックアップファイルを作成（mtime を明示的に設定、古い順: 01→12）
for i in $(seq 1 12); do
  fname="usage_20260227_$(printf '%02d' "$i")0000.db"
  touch "$BACKUP_DIR/$fname"
  # touch -t CCYYMMDDhhmm: 分を変えて古い→新しいの順に
  touch -t "2026022700$(printf '%02d' "$i")" "$BACKUP_DIR/$fname"
done

# build-and-install.sh L29 と同じローテーションロジック
ls -t "$BACKUP_DIR"/usage_*.db 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true

remaining=$(ls "$BACKUP_DIR"/usage_*.db 2>/dev/null | wc -l | tr -d ' ')
assert_eq "残りファイル数が 10" "10" "$remaining"

# 最も古い2個（01, 02）が削除されていること
if [ -f "$BACKUP_DIR/usage_20260227_010000.db" ]; then
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: 最も古いファイル（01）が削除されていない"
  echo "  FAIL: 最も古いファイル（01）が削除されていない"
else
  PASSED=$((PASSED + 1))
  echo "  PASS: 最も古いファイル（01）が削除されている"
fi

if [ -f "$BACKUP_DIR/usage_20260227_020000.db" ]; then
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: 2番目に古いファイル（02）が削除されていない"
  echo "  FAIL: 2番目に古いファイル（02）が削除されていない"
else
  PASSED=$((PASSED + 1))
  echo "  PASS: 2番目に古いファイル（02）が削除されている"
fi

# 最新（12）が残っていること
if [ -f "$BACKUP_DIR/usage_20260227_120000.db" ]; then
  PASSED=$((PASSED + 1))
  echo "  PASS: 最新ファイル（12）が残っている"
else
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: 最新ファイル（12）が削除されている"
  echo "  FAIL: 最新ファイル（12）が削除されている"
fi

echo ""

# --- Summary ---
echo "=== 結果: $PASSED passed, $FAILED failed ==="
if [ "$FAILED" -gt 0 ]; then
  echo -e "\n失敗したテスト:$ERRORS"
  exit 1
fi
