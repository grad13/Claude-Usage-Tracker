---
File: tests/tools/test_lib_functions.py
Lines: 63
Judgment: should
Issues: [S6]
---

# test_lib_functions.py

## 問題点

### 1. [S6] 責務混在 — 2つの独立モジュールを1ファイルでテスト

**現状**: `lib/version.py` の `get_app_version` と `lib/launchservices.py` の `deregister_stale_apps` を1つのテストファイルで扱っている（L1-6のdocstring、L16-17のimport）。
**本質**: version.py と launchservices.py は依存関係のない独立モジュール。テストファイル名 `test_lib_functions` も汎用的で、どのモジュールのテストか特定できない。モジュール追加時にこのファイルが際限なく肥大化するリスクがある。
**あるべき姿**: `test_version.py` と `test_launchservices.py` にモジュール単位で分割する。
