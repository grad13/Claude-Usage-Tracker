#!/bin/bash
# build-and-install.sh のデータ保護ロジック + rollback.sh の単体テスト
#
# テストケース:
#   1-4.   データ保護: 行消失検出 SQL
#   5.     DB バックアップローテーション（10個保持）
#   6-8.   バイナリバックアップ: バージョン付きリネーム / unknown / 上書き
#   9-11.  rollback.sh: 復元 / 存在しないバージョン / 引数なし一覧
#   12-15. data-protection.sh: 上書きリストア / 削除リストア / 未存在スキップ / 未変更
#
# 使い方: ./code/tools/test-build-install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/data-protection.sh"
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

# build-and-install.sh L156-160 と同じ行消失検出 SQL
# backup にあって current にない行数を返す（0 = 消失なし）
run_lost_check() {
  local current_db="$1"
  local backup_db="$2"
  sqlite3 "$current_db" "
    ATTACH '${backup_db}' AS backup;
    SELECT COUNT(*) FROM backup.usage_log
    WHERE rowid NOT IN (SELECT rowid FROM main.usage_log);
  " 2>/dev/null || echo "-1"
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

echo "=== build-and-install.sh データ保護テスト ==="
echo ""

# --- Test 1: 行消失が検出される ---
echo "--- Test 1: backup にあって current にない行 → LOST > 0 ---"
T1="$TMPDIR_BASE/t1"
mkdir -p "$T1"
BACKUP_DB="$T1/backup.db"
CURRENT_DB="$T1/current.db"

create_usage_db "$BACKUP_DB"
create_usage_db "$CURRENT_DB"

# backup: 3行
sqlite3 "$BACKUP_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1001, 10.0);"
sqlite3 "$BACKUP_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1002, 20.0);"
sqlite3 "$BACKUP_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1003, 30.0);"

# current: 1行のみ（2行消失）
sqlite3 "$CURRENT_DB" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (1001, 10.0);"

lost=$(run_lost_check "$CURRENT_DB" "$BACKUP_DB")
assert_eq "消失行数が 2" "2" "$lost"

echo ""

# --- Test 2: 行消失なし ---
echo "--- Test 2: backup と current が同一 → LOST = 0 ---"
T2="$TMPDIR_BASE/t2"
mkdir -p "$T2"
BACKUP_DB_2="$T2/backup.db"
CURRENT_DB_2="$T2/current.db"

create_usage_db "$BACKUP_DB_2"
create_usage_db "$CURRENT_DB_2"

# 同じ3行を両方に挿入
for ts in 2001 2002 2003; do
  sqlite3 "$BACKUP_DB_2" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES ($ts, 50.0);"
  sqlite3 "$CURRENT_DB_2" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES ($ts, 50.0);"
done

lost=$(run_lost_check "$CURRENT_DB_2" "$BACKUP_DB_2")
assert_eq "消失行数が 0" "0" "$lost"

echo ""

# --- Test 3: current に新しい行が追加されても検出しない ---
echo "--- Test 3: current に追加行があっても LOST = 0 ---"
T3="$TMPDIR_BASE/t3"
mkdir -p "$T3"
BACKUP_DB_3="$T3/backup.db"
CURRENT_DB_3="$T3/current.db"

create_usage_db "$BACKUP_DB_3"
create_usage_db "$CURRENT_DB_3"

# backup: 2行
sqlite3 "$BACKUP_DB_3" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (3001, 10.0);"
sqlite3 "$BACKUP_DB_3" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (3002, 20.0);"

# current: backup の2行 + 新しい1行
sqlite3 "$CURRENT_DB_3" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (3001, 10.0);"
sqlite3 "$CURRENT_DB_3" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (3002, 20.0);"
sqlite3 "$CURRENT_DB_3" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (3003, 30.0);"

lost=$(run_lost_check "$CURRENT_DB_3" "$BACKUP_DB_3")
assert_eq "消失行数が 0（新しい行は無視）" "0" "$lost"

echo ""

# --- Test 4: backup が空の場合にエラーにならない ---
echo "--- Test 4: 空 backup → LOST = 0 ---"
T4="$TMPDIR_BASE/t4"
mkdir -p "$T4"
BACKUP_DB_4="$T4/backup.db"
CURRENT_DB_4="$T4/current.db"

create_usage_db "$BACKUP_DB_4"
create_usage_db "$CURRENT_DB_4"

# current: 3行、backup: 空
sqlite3 "$CURRENT_DB_4" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (4001, 50.0);"
sqlite3 "$CURRENT_DB_4" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (4002, 60.0);"
sqlite3 "$CURRENT_DB_4" "INSERT INTO usage_log (timestamp, hourly_percent) VALUES (4003, 70.0);"

lost=$(run_lost_check "$CURRENT_DB_4" "$BACKUP_DB_4")
assert_eq "空 backup での LOST が 0" "0" "$lost"

echo ""

# --- Test 5: バックアップファイルローテーション（10個保持） ---
echo "--- Test 5: バックアップローテーション（12→10、古い2個削除） ---"
T5="$TMPDIR_BASE/t5"
BACKUP_DIR="$T5/backups"
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

# === バイナリバックアップ・ロールバック テスト ===
echo "=== バイナリバックアップ・ロールバック テスト ==="
echo ""

# --- Test 6: バージョン付きリネームバックアップ ---
echo "--- Test 6: バイナリバックアップ — バージョン付きリネーム ---"
T6="$TMPDIR_BASE/t6"
INSTALL_T6="$T6/Applications"
mkdir -p "$INSTALL_T6/TestApp.app/Contents"

# 偽 Info.plist を作成
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.9.1" \
  "$INSTALL_T6/TestApp.app/Contents/Info.plist"

# build-and-install.sh と同じバックアップロジック
APP_DIR="$INSTALL_T6/TestApp.app"
if [ -d "$APP_DIR" ]; then
    PLIST="$APP_DIR/Contents/Info.plist"
    if [ -f "$PLIST" ]; then
        CV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$PLIST" 2>/dev/null || echo "unknown")
    else
        CV="unknown"
    fi
    BA="$INSTALL_T6/TestApp.app.v${CV}"
    rm -rf "$BA"
    mv "$APP_DIR" "$BA"
fi

if [ -d "$INSTALL_T6/TestApp.app.v0.9.1" ]; then
  PASSED=$((PASSED + 1))
  echo "  PASS: .app.v0.9.1 が作成された"
else
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: .app.v0.9.1 が作成されていない"
  echo "  FAIL: .app.v0.9.1 が作成されていない"
fi

if [ ! -d "$INSTALL_T6/TestApp.app" ]; then
  PASSED=$((PASSED + 1))
  echo "  PASS: 元の .app が消えている（mv 成功）"
else
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: 元の .app がまだ残っている"
  echo "  FAIL: 元の .app がまだ残っている"
fi

echo ""

# --- Test 7: Info.plist なし → unknown フォールバック ---
echo "--- Test 7: バイナリバックアップ — Info.plist なし → vunknown ---"
T7="$TMPDIR_BASE/t7"
INSTALL_T7="$T7/Applications"
mkdir -p "$INSTALL_T7/TestApp.app/Contents"
# Info.plist を作成しない

APP_DIR="$INSTALL_T7/TestApp.app"
if [ -d "$APP_DIR" ]; then
    PLIST="$APP_DIR/Contents/Info.plist"
    if [ -f "$PLIST" ]; then
        CV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$PLIST" 2>/dev/null || echo "unknown")
    else
        CV="unknown"
    fi
    BA="$INSTALL_T7/TestApp.app.v${CV}"
    rm -rf "$BA"
    mv "$APP_DIR" "$BA"
fi

if [ -d "$INSTALL_T7/TestApp.app.vunknown" ]; then
  PASSED=$((PASSED + 1))
  echo "  PASS: .app.vunknown が作成された"
else
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: .app.vunknown が作成されていない"
  echo "  FAIL: .app.vunknown が作成されていない"
fi

echo ""

# --- Test 8: 同バージョン上書き ---
echo "--- Test 8: バイナリバックアップ — 同バージョン上書き ---"
T8="$TMPDIR_BASE/t8"
INSTALL_T8="$T8/Applications"
mkdir -p "$INSTALL_T8/TestApp.app.v0.9.1"
echo "old" > "$INSTALL_T8/TestApp.app.v0.9.1/marker"
mkdir -p "$INSTALL_T8/TestApp.app/Contents"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.9.1" \
  "$INSTALL_T8/TestApp.app/Contents/Info.plist"
echo "new" > "$INSTALL_T8/TestApp.app/marker"

APP_DIR="$INSTALL_T8/TestApp.app"
if [ -d "$APP_DIR" ]; then
    PLIST="$APP_DIR/Contents/Info.plist"
    if [ -f "$PLIST" ]; then
        CV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$PLIST" 2>/dev/null || echo "unknown")
    else
        CV="unknown"
    fi
    BA="$INSTALL_T8/TestApp.app.v${CV}"
    rm -rf "$BA"
    mv "$APP_DIR" "$BA"
fi

marker_content=$(cat "$INSTALL_T8/TestApp.app.v0.9.1/marker")
assert_eq "既存バックアップが上書きされた（marker=new）" "new" "$marker_content"

echo ""

# --- Test 9: rollback.sh で実際に復元 ---
echo "--- Test 9: rollback.sh — 実スクリプトで復元、バックアップは残る ---"
T9="$TMPDIR_BASE/t9"
INSTALL_T9="$T9/Applications"
mkdir -p "$INSTALL_T9/ClaudeUsageTracker.app"
echo "current" > "$INSTALL_T9/ClaudeUsageTracker.app/marker"
mkdir -p "$INSTALL_T9/ClaudeUsageTracker.app.v0.9.1"
echo "backup" > "$INSTALL_T9/ClaudeUsageTracker.app.v0.9.1/marker"

ROLLBACK_TEST_MODE=1 INSTALL_DIR="$INSTALL_T9" "$SCRIPT_DIR/rollback.sh" v0.9.1 > /dev/null 2>&1

restored=$(cat "$INSTALL_T9/ClaudeUsageTracker.app/marker")
assert_eq "復元後の中身が backup と同一" "backup" "$restored"

if [ -d "$INSTALL_T9/ClaudeUsageTracker.app.v0.9.1" ]; then
  PASSED=$((PASSED + 1))
  echo "  PASS: バックアップが残っている（cp -R なので消えない）"
else
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: バックアップが消えている"
  echo "  FAIL: バックアップが消えている"
fi

echo ""

# --- Test 10: rollback.sh — 存在しないバージョン → エラー終了 ---
echo "--- Test 10: rollback.sh — 存在しないバージョン → exit 1 ---"
T10="$TMPDIR_BASE/t10"
INSTALL_T10="$T10/Applications"
mkdir -p "$INSTALL_T10"

ROLLBACK_EXIT=0
ROLLBACK_TEST_MODE=1 INSTALL_DIR="$INSTALL_T10" "$SCRIPT_DIR/rollback.sh" v9.9.9 > /dev/null 2>&1 || ROLLBACK_EXIT=$?
assert_eq "存在しないバージョンで exit 1" "1" "$ROLLBACK_EXIT"

echo ""

# --- Test 11: rollback.sh — 引数なしでバージョン一覧表示 ---
echo "--- Test 11: rollback.sh — 引数なしでバージョン一覧 → exit 1 ---"
T11="$TMPDIR_BASE/t11"
INSTALL_T11="$T11/Applications"
mkdir -p "$INSTALL_T11/ClaudeUsageTracker.app.v0.9.1"
mkdir -p "$INSTALL_T11/ClaudeUsageTracker.app.v0.9.2"

LIST_OUTPUT=$(ROLLBACK_TEST_MODE=1 INSTALL_DIR="$INSTALL_T11" "$SCRIPT_DIR/rollback.sh" 2>&1 || true)
if echo "$LIST_OUTPUT" | grep -q "v0.9.1" && echo "$LIST_OUTPUT" | grep -q "v0.9.2"; then
  PASSED=$((PASSED + 1))
  echo "  PASS: バージョン一覧に v0.9.1 と v0.9.2 が表示された"
else
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: バージョン一覧が正しくない: $LIST_OUTPUT"
  echo "  FAIL: バージョン一覧が正しくない: $LIST_OUTPUT"
fi

echo ""

# === data-protection.sh 関数テスト（build-and-install.sh が使う実関数をテスト） ===
echo "=== data-protection.sh ファイル保護関数テスト ==="
echo ""

# --- Test 12: snapshot + 上書き → restore_file_if_changed でリストア ---
echo "--- Test 12: ファイル上書き → restore_file_if_changed でリストア ---"
T12="$TMPDIR_BASE/t12"
mkdir -p "$T12"
echo '{"original":"cookies"}' > "$T12/session-cookies.json"

snapshot_file "$T12/session-cookies.json"

# テストが上書きをシミュレート
echo '{"corrupted":"by-test"}' > "$T12/session-cookies.json"

RESTORE_RET=0
restore_file_if_changed "$T12/session-cookies.json" || RESTORE_RET=$?
assert_eq "戻り値が 1（リストアした）" "1" "$RESTORE_RET"

restored=$(cat "$T12/session-cookies.json")
assert_eq "上書き後にオリジナルが復元された" '{"original":"cookies"}' "$restored"

if [ -f "$T12/session-cookies.json.backup" ]; then
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: .backup が残っている（クリーンアップされていない）"
  echo "  FAIL: .backup が残っている（クリーンアップされていない）"
else
  PASSED=$((PASSED + 1))
  echo "  PASS: .backup がクリーンアップされた"
fi

echo ""

# --- Test 13: snapshot + 削除 → restore_file_if_changed でリストア ---
echo "--- Test 13: ファイル削除 → restore_file_if_changed でリストア ---"
T13="$TMPDIR_BASE/t13"
mkdir -p "$T13"
echo '{"original":"cookies"}' > "$T13/session-cookies.json"

snapshot_file "$T13/session-cookies.json"

# テストが削除をシミュレート
rm "$T13/session-cookies.json"

RESTORE_RET=0
restore_file_if_changed "$T13/session-cookies.json" || RESTORE_RET=$?
assert_eq "戻り値が 2（削除からリストア）" "2" "$RESTORE_RET"

restored=$(cat "$T13/session-cookies.json")
assert_eq "削除後にリストアされた" '{"original":"cookies"}' "$restored"

echo ""

# --- Test 14: ファイル未存在 → snapshot + restore がスキップ ---
echo "--- Test 14: ファイル未存在 → snapshot + restore がスキップ ---"
T14="$TMPDIR_BASE/t14"
mkdir -p "$T14"
# session-cookies.json を作成しない

snapshot_file "$T14/session-cookies.json"

RESTORE_RET=0
restore_file_if_changed "$T14/session-cookies.json" || RESTORE_RET=$?
assert_eq "戻り値が 0（スキップ）" "0" "$RESTORE_RET"

echo ""

# --- Test 15: ファイル未変更 → restore が変更なしを返す ---
echo "--- Test 15: ファイル未変更 → restore が変更なし（戻り値 0） ---"
T15="$TMPDIR_BASE/t15"
mkdir -p "$T15"
echo '{"unchanged":"data"}' > "$T15/settings.json"

snapshot_file "$T15/settings.json"
# ファイルを変更しない

RESTORE_RET=0
restore_file_if_changed "$T15/settings.json" || RESTORE_RET=$?
assert_eq "戻り値が 0（変更なし）" "0" "$RESTORE_RET"

content=$(cat "$T15/settings.json")
assert_eq "内容が変わっていない" '{"unchanged":"data"}' "$content"

if [ -f "$T15/settings.json.backup" ]; then
  FAILED=$((FAILED + 1))
  ERRORS="$ERRORS\n  FAIL: .backup が残っている"
  echo "  FAIL: .backup が残っている"
else
  PASSED=$((PASSED + 1))
  echo "  PASS: .backup がクリーンアップされた"
fi

echo ""

# --- Summary ---
echo "=== 結果: $PASSED passed, $FAILED failed ==="
if [ "$FAILED" -gt 0 ]; then
  echo -e "\n失敗したテスト:$ERRORS"
  exit 1
fi
