---
File: tools/lib/runner.py
Lines: 29
Judgment: should
Issues: [check/allow_fail 2フラグの意味論が冗長]
---
# runner.py

## 使われ方
- `build_and_install.py`, `rollback.py`, `launchservices.py` から呼ばれる唯一の subprocess 実行関数
- デフォルト（`check=True`）: ビルド・署名・コピーなど失敗が致命的なコマンド
- `allow_fail=True`: killall 系（対象プロセスが存在しなくても正常）
- `check=False`: GetFileInfo, lsregister dump（戻り値を見て後続ロジックで判断）

## 問題点

### 1. check/allow_fail 2フラグが冗長で意味論が混乱
**現状**: `check` (bool) と `allow_fail` (bool) の2パラメータで4状態を作れるが、実際の挙動は「raise する」か「WARNING で続行」の2つだけ。docstring 自身が `check=False, allow_fail=False` を "same as allow_fail" と認めている。呼び出し側も `allow_fail=True` と `check=False` を同じ意味で使い分けている。

**本質**: 「失敗時の振る舞い」という単一の軸を2つのフラグで表現しているため、組み合わせの意味が不明確になる。`check=True, allow_fail=True` は「チェックするが失敗を許容する」という矛盾した表明。

**あるべき姿**: 失敗時の振る舞いを1つのパラメータで表現する。例: `on_error: Literal["raise", "warn", "silent"]`。現在の利用パターンは `raise`（デフォルト）と `warn`（killall / 情報取得系）の2つに集約できる。`silent` は将来の拡張余地。
