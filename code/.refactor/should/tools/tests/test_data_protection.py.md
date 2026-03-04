---
File: tools/tests/test_data_protection.py
Lines: 290
Judgment: should
Issues: [責務混在 — build_and_install.py のロジックテストと data_protection モジュールのテストが同居]
---

# test_data_protection.py

## 問題点

### 1. 別モジュールのロジックテストが混在している

**現状**: Test 1-5（行 84-136）は `data_protection` モジュールではなく `build_and_install.py` の lost row detection SQL と backup rotation ロジックをテストしている。ヘルパー関数 `_create_usage_db`、`_insert_rows`、`_run_lost_check`（行 33-81）は `build_and_install.py` のロジックをインラインで複製しており、`data_protection` からは何もインポートしていない。一方 Test 12-19（行 139-290）は `data_protection.protect_files` を正しくテストしている。

**本質**: ファイル名が `test_data_protection.py` であるにもかかわらず、テストの約3分の1は別モジュール（`build_and_install.py`）の責務をテストしている。これにより (1) テストの所在が不明瞭になる（build_and_install のロジック変更時にこのファイルを修正する必要があると気づきにくい）、(2) ロジックがインライン複製されているため本体との乖離リスクがある。

**あるべき姿**: `build_and_install.py` 関連のテスト（Test 1-5 + ヘルパー）を `test_build_and_install.py` に分離する。lost row detection SQL もインライン複製ではなく `build_and_install.py` から関数として抽出・インポートしてテストすべき。`test_data_protection.py` には `data_protection` モジュールのテスト（Test 12-19）のみを残す。
