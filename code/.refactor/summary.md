# Refactor Analysis Summary — code/tools/

**Date**: 2026-03-15
**Scope**: code/tools/ (Python/Shell ビルドツール)
**Files analyzed**: 6 (+ __init__.py skipped as empty)

## Results

| File | Lines | Judgment |
|------|-------|----------|
| tools/build_and_install.py | 444 | **should** |
| tools/rollback.py | 124 | clean |
| tools/check_notarization.sh | 45 | clean |
| tools/lib/data_protection.py | 146 | clean |
| tools/lib/launchservices.py | 69 | clean |
| tools/lib/version.py | 19 | clean |

## should (1 file)

### tools/build_and_install.py

1. **register_and_verify に5責務が集中** — バンドルビット検証、LaunchServices登録、デプロイ検証ゲート、データ整合性チェック、Dockリフレッシュ+起動が1関数に詰まっている
2. **DBバックアップ/整合性チェックがデプロイロジックと混在** — `backup_database`, `rotate_backups`, `check_lost_rows` が既存の `lib/` に分離可能

詳細: `code/.refactor/should/tools/build_and_install.py.md`

## must (0 files)

500行超のファイルなし。

## clean (5 files)

- tools/rollback.py — 単一責務（ロールバック処理）
- tools/check_notarization.sh — 単一責務（notarization確認）
- tools/lib/data_protection.py — 単一責務（ファイル保護）
- tools/lib/launchservices.py — 単一責務（LaunchServices操作）
- tools/lib/version.py — 19行のユーティリティ
