---
File: tests/tools/test_build_and_install_supplement.py
Lines: 234
Judgment: should
Issues: [S6, S7]
---

# test_build_and_install_supplement.py

## 問題点

### 1. [S6] 責務混在 — 複数モジュールを1ファイルでテスト

**現状**: Test 33-37 は `build_and_install` モジュール (line 20: `import build_and_install as bai`) をテストし、Test 38-39 は `data_protection` モジュール (line 211: `from data_protection import shelter_file`) をテストしている。
**本質**: 異なるモジュールのテストが1ファイルに混在しており、テスト対象の責務境界が曖昧。`data_protection.shelter_file` のテストは `test_data_protection.py` に属すべき。
**あるべき姿**: `shelter_file` のテストは `tests/tools/test_data_protection.py` に分離し、本ファイルは `build_and_install` のテストのみにする。

### 2. [S7] 手書き部分モック — subprocess.run のアドホックな差し替え

**現状**: Test 36 (line 150-161) と Test 37 (line 184-194) で `mock_run` 関数を手書きし、`monkeypatch.setattr(bai.subprocess, "run", mock_run)` で差し替えている。関数内部で条件分岐 (`if cmd[0] == "GetFileInfo"`) してレスポンスを切り替えるアドホックなパターン。
**本質**: `unittest.mock.patch` + `side_effect` の標準パターンを使えば、呼び出し引数の検証・呼び出し回数の追跡が自動的に得られる。手書き関数では `calls` リストを自前管理 (line 182-186) する必要があり、保守コストが高い。
**あるべき姿**: `@patch("build_and_install.subprocess.run")` + `side_effect` で条件分岐を実装し、`mock.call_args_list` で呼び出し検証する。
