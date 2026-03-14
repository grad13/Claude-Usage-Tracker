# Refactor Tests Summary — tools系

**実行日**: 2026-03-15
**対象**: `tests/tools/` 配下 21ファイル（conftest.py含む）

## 結果サマリー

| 判定 | 件数 | ファイル |
|------|------|----------|
| **must** | 1 | test_build_and_install_supplement2.py (658行) |
| **should** | 9 | 下記参照 |
| **clean** | 11 | 下記参照 |

## must（必須リファクタリング）

| ファイル | 行数 | 問題 | 概要 |
|----------|------|------|------|
| test_build_and_install_supplement2.py | 658 | M2, S6, S7 | 500行超、13テストクラス混在、手書きモック |

## should（推奨リファクタリング）

| ファイル | 行数 | 問題 | 概要 |
|----------|------|------|------|
| test_binary_backup_supplement.py | 195 | S6, S7 | 3関数混在テスト、手書きSQLiteフィクスチャ |
| test_rollback_supplement2.py | 194 | S7 | nonlocal状態追跡の手書きモック |
| test_data_protection_supplement2.py | 187 | S7 | __import__動的インポート+条件付きモック |
| test_build_and_install_supplement.py | 182 | S6, S7 | backup+bundle bit混在、重複モック |
| test_deploy_gate.py | 181 | S6, S7 | build_app+verify_widget混在、重複モック |
| test_binary_backup.py | 170 | S6, S7 | backup+atomic install混在、手書きヘルパー |
| test_data_protection_supplement.py | 148 | S6, S7 | 5関数混在、実装結合モック |
| test_launchservices_supplement.py | 131 | S7 | ハードコードモックデータ文字列 |
| test_build_and_install.py | 113 | S6 | ファイル名とテスト内容不一致（実際はdb_backup） |

## clean（問題なし）

| ファイル | 行数 |
|----------|------|
| test_launchservices_supplement2.py | 173 |
| test_data_protection.py | 171 |
| test_rollback.py | 113 |
| test_rollback_supplement.py | 109 |
| test_deploy_integration.py | 94 |
| test_runner.py | 84 |
| test_find_derived_data.py | 82 |
| test_version_supplement.py | 71 |
| conftest.py | 46 |
| test_version.py | 35 |
| test_launchservices.py | 31 |

## 問題パターン別集計

| 問題ID | 説明 | 該当数 |
|--------|------|--------|
| M2 | 500行超 | 1 |
| S6 | 責務混在 | 7 |
| S7 | 手書き部分モック | 8 |
| S8 | xcodebuild エラー | 0 |

## 主要な改善方向

1. **test_build_and_install_supplement2.py の分割**（must）: 658行・13クラスを機能別に分割（build, install, register等）
2. **ファイル名修正**: test_build_and_install.py → test_db_backup.py（内容はdb_backupのテスト）
3. **手書きモックの fixture 化**: 8ファイルで手書きモック/ヘルパーを検出。conftest.py への共有fixture抽出を推奨
4. **責務分離**: 7ファイルで複数関数/モジュールの混在テスト。機能単位でのファイル分割を推奨
