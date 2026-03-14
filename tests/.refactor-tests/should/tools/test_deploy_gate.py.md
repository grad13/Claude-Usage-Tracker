---
File: tests/tools/test_deploy_gate.py
Lines: 182
Judgment: should
Issues: [S6, S7]
---

# test_deploy_gate.py

## 問題点

### 1. [S6] 責務混在：build_app() と _verify_widget_deployment() のテストが同一ファイル

**現状**:
- TestStaleXctestRemoval クラス（Tests 1-3）: build_app() の stale xctest 削除機能
- TestVerificationGate クラス（Tests 4-7）: _verify_widget_deployment() の 3 条件チェック
- 異なる関数、異なる責務、異なるテスト戦略が混在

**本質**:
ビルド（xctest 削除）とデプロイ検証（pluginkit/LaunchServices チェック）は独立した責務。
テストファイルを分離することで：
- 各テストの意図が明確になる
- テスト実行時の focus が容易（`pytest tests/tools/test_build_app.py` vs `test_deploy_gate.py`）
- 将来のメンテナンス時に責務境界が明確

**あるべき姿**:
- `test_build_app.py`: TestStaleXctestRemoval （xctest 削除テスト）
- `test_deploy_gate.py`: TestVerificationGate （デプロイ検証テスト）

---

### 2. [S7] 手書きモック関数：_make_completed_process, _make_pluginkit_stdout

**現状**:
- Lines 31-40: `_make_completed_process()`, `_mock_run_success()`
- Lines 114-119: `_make_pluginkit_stdout()` メソッド
- インラインモック（TestVerificationGate の各テスト内）: lines 127-130, 141-144, 157-160, 173-176

**本質**:
Mock オブジェクト生成ロジックが複数の場所に散在しており、保守性が低い。
- pluginkit stdout パターンが `_make_pluginkit_stdout()` にのみ集約
- CompletedProcess 生成が `_make_completed_process()` に集約されているが、呼び出し側でパターンが異なる
- 各テスト内でインラインで `mock_run` クロージャを定義（重複あり）

**あるべき姿**:
- Mock fixture（`conftest.py` または クラス内）に統一
- 例：
  ```python
  @pytest.fixture
  def mock_completed_process():
      def _make(stdout="", stderr="", returncode=0):
          return subprocess.CompletedProcess(...)
      return _make

  @pytest.fixture
  def pluginkit_stdout_builder():
      def _make(found=True, ghost=False):
          ...
      return _make
  ```
- インラインの `mock_run` クロージャを再利用可能な fixture に変換
