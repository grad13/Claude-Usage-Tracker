# Diagnosis: test_launchservices_supplement.py

## 対象テスト
- `tests/tools/test_launchservices_supplement.py`

## 対象ソース
- `code/tools/lib/launchservices.py`

## 失敗テスト

### test_deregister_stale_apps_derived_data — Class A6
### test_deregister_stale_apps_trash — Class A6
### test_register_app — Class A6
### test_dump_widget_registration_found — Class A6
### test_dump_widget_registration_not_found — Class A6

**What**: 全5テストが `with patch("launchservices.subprocess.run")` でモックしているが、`launchservices` モジュールは `subprocess` を直接インポートしていない。`from runner import run` で `runner.run` 関数を使用している。

**Why**: `launchservices.py` の実装:
```python
from runner import run
```
`subprocess` モジュールへの参照が存在しないため、`patch("launchservices.subprocess.run")` は `AttributeError: module 'launchservices' has no attribute 'subprocess'` を発生させる。

**How**: モック対象を `launchservices.run` に変更。ただし `run` は `runner.run` のラッパーで `subprocess.run` とはシグネチャが異なるため、テストのアサーションも `runner.run` の呼び出し規約に合わせる必要がある。

具体的には:
- `deregister_stale_apps` は `run([LSREGISTER, "-u", ...], on_error="warn", label="deregister DD")` を呼ぶ
- `register_app` は `run([LSREGISTER, "-f", ...], label="register app")` を呼ぶ
- `dump_widget_registration` は `run([LSREGISTER, "-dump"], on_error="warn", label="lsregister dump")` を呼ぶ

## 成功テスト
なし（全5テスト失敗）
