---
File: tests/tools/test_build_and_install_supplement2.py
Lines: 659
Judgment: must
Issues: [M2, S6, S7]
---

# test_build_and_install_supplement2.py

## 問題点

### 1. [M2] ファイルが500行を超えている（659行）

**現状**:
- ファイル総行数: 659行
- 複数のテストクラス（13クラス）が1ファイルにまとめられている
- 各クラス: TestFindDerivedDataDirEdgeCases, TestRunTestGate, TestBuildApp, TestQuitRunningApp, TestInstallApp, TestVerifyInstalledWidget, TestVerifyBundleBitsEdge, TestRegisterAndClean, TestCheckDataIntegrityEdgeCases, TestRefreshAndLaunch, TestMainPipeline

**本質**:
- 単一ファイルで500行を超えると保守性が低下する
- 機能ごと（find_derived_data_dir, run_test_gate, build_app など）にモジュール化されるべき
- テスト発見、デバッグ時のナビゲーション困難

**あるべき姿**:
- 各主要機能ごとに別ファイル化（例: test_build_app.py, test_install_app.py, test_main_pipeline.py）
- 単一責務の原則（SRP）に従う
- 300～400行以下の複数ファイルに分割

---

### 2. [S6] 複数モジュール・機能を1テストファイルでテスト（責務混在）

**現状**:
- build_and_install.py の11個以上の独立した機能をテスト：
  - find_derived_data_dir() — ディレクトリ検索（FD-05, FD-06）
  - run_test_gate() — テスト実行（TG-01, TG-02）
  - build_app() — ビルド（BA-01～04）
  - quit_running_app() — プロセス終了（QA-01）
  - install_app() — アプリインストール（IA-02, IA-04）
  - verify_installed_widget() — ウィジェット検証（VW-01～04）
  - verify_bundle_bits() — バンドル検証（VB-03）
  - register_and_clean() — 登録・クリーン（RC-01～03）
  - check_data_integrity() — データ整合性（CI-01, CI-04）
  - refresh_and_launch() — リフレッシュ・起動（RL-01）
  - main() — パイプライン全体（Main-01～05）

**本質**:
- 各機能は異なる責務を持ち、異なるスケール（単一関数 vs 統合パイプライン）
- find_derived_data_dir の問題と main() の問題は無関係
- テスト失敗時の原因特定が難しい
- テストの再利用性・組み合わせが低い

**あるべき姿**:
- 機能グループごとにテストファイル分割：
  - test_build.py — build_app, run_test_gate
  - test_install.py — install_app, verify_installed_widget
  - test_register.py — register_and_clean, deregister_stale_apps
  - test_verification.py — verify_bundle_bits, check_data_integrity
  - test_integration.py — main(), refresh_and_launch
- 各ファイルは1～2機能に集中

---

### 3. [S7] 手書きモック/スタブ（unittest.mock を使用していない部分がある）

**現状**:
- Lines 37-43: `_make_run_result()` — subprocess.CompletedProcess の手動構築
  ```python
  def _make_run_result(returncode=0, stdout="", stderr=""):
      r = MagicMock(spec=subprocess.CompletedProcess)
      r.returncode = returncode
      r.stdout = stdout
      r.stderr = stderr
      return r
  ```
- Lines 46-61: `_make_widget_binary()` — ウィジェットバイナリの手動作成
- Lines 230-235, 262-267: `run_side_effect()` — 関数内の副作用をハードコード実装
- Lines 375-379, 400-409, 424-433: run_side_effect() による codesign 出力シミュレーション

**本質**:
- unittest.mock が十分でない場合の代替手段だが、保守性が低い
- 各テストメソッド内に重複した setup ロジック
- 実際のファイルシステム操作（mkdir, write_bytes, utime）を含む（偽テスト境界の混在）
- モック戦略の一貫性がない

**あるべき姿**:
- 共有ヘルパーを pytest fixtures に転換
  ```python
  @pytest.fixture
  def mock_run_result():
      def _make(returncode=0, stdout="", stderr=""):
          r = MagicMock(spec=subprocess.CompletedProcess)
          r.returncode = returncode
          r.stdout = stdout
          r.stderr = stderr
          return r
      return _make
  ```
- 副作用の複雑な組み合わせは factory 化
- 実ファイルシステムは tmpdir fixture に集約

---

## 推奨される分割計画

```
test_build_and_install_supplement2.py （659行）
  ↓
tests/tools/test_find_derived_data.py （FD-05, FD-06: ~30行）
tests/tools/test_run_test_gate.py （TG-01, TG-02: ~35行）
tests/tools/test_build_app.py （BA-01～04: ~60行）
tests/tools/test_quit_running_app.py （QA-01: ~25行）
tests/tools/test_install_app.py （IA-02, IA-04: ~80行）
tests/tools/test_verify_installed_widget.py （VW-01～04: ~70行）
tests/tools/test_verify_bundle_bits.py （VB-03: ~25行）
tests/tools/test_register_and_clean.py （RC-01～03: ~100行）
tests/tools/test_check_data_integrity.py （CI-01, CI-04: ~35行）
tests/tools/test_refresh_and_launch.py （RL-01: ~30行）
tests/tools/test_main_pipeline.py （Main-01～05: ~150行 — 統合テスト）

conftest.py 新設: fixtures (_make_run_result, _make_widget_binary など)
```

---

## 分割時の注意

1. **共有ヘルパー**: conftest.py に集約
2. **fixtures**: tmp_path, monkeypatch は pytest 標準を活用
3. **Main-01～05**: 統合テストは test_main_pipeline.py に集約（最後のファイル）
4. **import 重複**: 各ファイルで `import build_and_install as bai` が必要
5. **docstring**: 各ファイルに機能説明を追加
