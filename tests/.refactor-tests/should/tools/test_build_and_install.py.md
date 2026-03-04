---
File: tests/tools/test_build_and_install.py
Lines: 124
Judgment: should
Issues: [S7]
---

# test_build_and_install.py

## 問題点

### 1. [S7] プロダクションコードをインポートせず、テスト内にロジックを再実装している

**現状**: テスト全体が `build_and_install.py` を一切インポートしていない。代わりに:
- `_run_lost_check` (59-68行) が lost-row detection SQL をテスト内に再実装
- `test_backup_rotation` (114-117行) が backup rotation ロジックをテスト内に再実装
- コメントでも「Same rotation logic as build_and_install.py」(114行) と明記されている通り、プロダクションコードのコピーをテストしている

**本質**: テストが検証しているのは「テスト内に書かれた再実装コード」であり、「プロダクションコードの実際の動作」ではない。プロダクション側のSQLやローテーションロジックが変更されてもテストは通り続けるため、回帰テストとして機能しない。テストとプロダクションコードの間に乖離が生じても検出できない。

**あるべき姿**: `build_and_install.py` から該当関数（lost-row detection、backup rotation）をインポートし、その関数を直接テストする。関数が切り出されていない場合は、まずプロダクションコード側でテスト可能な関数に分離し、それをテストで呼び出す構造にする。
