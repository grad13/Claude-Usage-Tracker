---
File: tests/tools/test_data_protection_supplement2.py
Lines: 188
Judgment: should
Issues: [S7]
---

# test_data_protection_supplement2.py

## 問題点

### 1. [S7] 手書き部分モック（manual side_effect composition）

**現状**:
```python
# Line 96-101
original_restore = __import__("data_protection", fromlist=["_restore_if_changed"])._restore_if_changed

def patched_restore(file, hash_before):
    if file.name == "file_a.json":
        raise OSError("disk error on file_a")
    return original_restore(file, hash_before)

with patch("data_protection._restore_if_changed", side_effect=patched_restore):
```

手書きコンディション付きモック（if 文で file.name を判定して一部だけ失敗させる）を定義しており、動的に `__import__` で元の関数を取得してから手動でラッピングしている。

**本質**:
`unittest.mock.patch` の `side_effect` パラメータで直接ラッパー関数を渡しているが、その関数本体に条件分岐ロジック（if file.name == "file_a.json"）を手で書いている。モックフレームワークの高度な機能（`side_effect` のリスト指定、`MagicMock` の条件付き return_value など）の活用不足。

**あるべき姿**:
- `unittest.mock.MagicMock` に `side_effect` をリスト指定して複数の戻り値を順序ガイドするか、
- または `MagicMock` の `side_effect` コールバックでも、すでにインポート済みの `_restore_if_changed` 関数を使うか
- あるいは `patch.object()` で直接置き換えることで、手書きコンディション分岐を最小化すべき

参考:
- `side_effect` リスト: `side_effect=[result1, result2, Exception("error")]` で順序制御
- `side_effect` 関数でも複雑なロジックはテストの別関数に分離

この補足テストは PF-05 ケース（restore 失敗時の他ファイル継続）を狙ったもので、その意図は正当だが、モックの書き方に改善の余地がある。
