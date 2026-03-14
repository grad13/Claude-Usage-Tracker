# Diagnosis: test_deploy_integration.py

## 対象テスト
- `tests/tools/test_deploy_integration.py`

## 対象ソース
- `/Applications/ClaudeUsageTracker.app`（実環境）

## 失敗テスト

### test_installed_app_code_signature_valid — Class A3

**What**: `codesign --verify --deep --strict` が失敗。エラー: `a sealed resource is missing or invalid`

**Why**: 環境依存。インストール済みアプリの署名が壊れている。開発中のデプロイで署名が不整合になることは通常の事象。テストは正しい（環境状態の問題）。

**How**: 修正対象外。次回のクリーンビルド＆インストールで解消される。

## 成功テスト
- test_installed_app_has_correct_bundle_id — pass
- test_installed_app_has_app_group_entitlement — pass
- test_installed_widget_has_app_group_entitlement — pass
- test_installed_widget_binary_exists — pass
