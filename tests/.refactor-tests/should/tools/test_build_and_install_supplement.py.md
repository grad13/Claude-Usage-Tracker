---
File: tests/tools/test_build_and_install_supplement.py
Lines: 183
Judgment: should
Issues: [S6, S7]
---

# test_build_and_install_supplement.py

## 問題点

### 1. [S6] 責務混在 — バックアップと bundle bit 検証が同一ファイルに混在

**現状**:
- テスト 33-35: `backup_database()` の動作を検証（DB作成、バックアップ生成、ローテーション）
- テスト 36-37: `verify_bundle_bits()` の bundle bit 検証

**本質**:
- 機能的に無関連な2つの責務が同一テストファイルに混在している
- `backup_database` は永続化（Keychain, ファイルシステム）担当
- `verify_bundle_bits` はビルド検証（macOS アトリビュート）担当
- テスト資源（fixture）も異なる：前者は tmpdir+SQLite、後者は GetFileInfo モック

**あるべき姿**:
- `test_backup_database.py` と `test_bundle_bits.py` に分割
- または補足テストの位置付けを明確にして、密接に関連するテストのみ集約

---

### 2. [S7] 手書きモック重複 — `run_side_effect()` の重複実装

**現状**:
```python
# Test 36 (行 145-152)
def run_side_effect(cmd, **kwargs):
    result = MagicMock()
    result.returncode = 0
    if cmd[0] == "GetFileInfo":
        result.stdout = f'directory: "{app_path}"\nattributes: avbstclinmedz\n'
    else:
        result.stdout = ""
    return result

# Test 37 (行 169-176) — 同一ロジック、属性値のみ異なる
def run_side_effect(cmd, **kwargs):
    result = MagicMock()
    result.returncode = 0
    if cmd[0] == "GetFileInfo":
        result.stdout = f'directory: "{app_path}"\nattributes: avBstclinmedz\n'  # 'b' → 'B'
    else:
        result.stdout = ""
    return result
```

**本質**:
- モック関数の実装が2回重複している
- 本来は shared fixture で定義すべき共通部分
- テスト間で単一の差分（attributes の大文字/小文字）しかない

**あるべき姿**:
```python
@pytest.fixture
def mock_bundle_bit_result(request):
    """Parametrizable GetFileInfo result mock."""
    bundle_bit = request.param if hasattr(request, 'param') else 'B'

    def run_side_effect(cmd, **kwargs):
        result = MagicMock()
        result.returncode = 0
        if cmd[0] == "GetFileInfo":
            result.stdout = f'directory: "..."\nattributes: av{bundle_bit}stclinmedz\n'
        else:
            result.stdout = ""
        return result

    return run_side_effect
```

- または `parametrize` で attributes を差し替え
