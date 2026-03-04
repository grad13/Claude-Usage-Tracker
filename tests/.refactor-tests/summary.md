# refactor-tests: tools系テスト分析サマリー

**実行日**: 2026-03-04
**対象**: `tests/tools/` 配下の全テストファイル（10ファイル, 1178行）

## 結果概要

| 判定 | 件数 |
|------|------|
| must | 0 |
| should | 2 |
| clean | 8 |

## should（推奨対処）

| ファイル | 行数 | 問題ID | 概要 |
|----------|------|--------|------|
| test_build_and_install.py | 124 | S7 | プロダクションコード未インポート。ロジック再実装をテスト内に持ち、回帰テストとして機能しない |
| test_lib_functions.py | 63 | S6 | version.py と launchservices.py の2独立モジュールを1ファイルに混在 |

## clean（問題なし）

| ファイル | 行数 |
|----------|------|
| test_data_protection.py | 171 |
| test_binary_backup.py | 170 |
| test_build_and_install_supplement.py | 133 |
| test_launchservices_supplement.py | 131 |
| test_data_protection_supplement.py | 120 |
| test_rollback.py | 113 |
| test_rollback_supplement.py | 109 |
| test_lib_functions.py の conftest.py | 46 |

## 詳細

- `tests/.refactor-tests/should/tools/test_build_and_install.py.md`
- `tests/.refactor-tests/should/tools/test_lib_functions.py.md`
