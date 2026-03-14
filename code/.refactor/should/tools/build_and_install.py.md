---
File: tools/build_and_install.py
Lines: 427
Judgment: should
Issues: [mtime-fallback, mixed-responsibilities, redundant-deregister, confusing-runner-api, magic-sleeps]
---

# build_and_install.py

## 使われ方

- **呼び出し元**: `.claude/skills/deploy/SKILL.md` が定義するデプロイスキル。ユーザーが `/deploy` を実行すると `python3 ./code/tools/build_and_install.py` が呼ばれる
- **タイミング**: 手動デプロイ時（開発中に繰り返し実行される）
- **フロー**: DB バックアップ → ファイル保護 → テスト → ビルド → アトミックインストール → LS 登録 → 検証 → 起動
- **関連**: `rollback.py` がインストールの逆操作（バックアップからの復元）を担当。`lib/` の 5 モジュールに個別責務を委譲

## 問題点

### 1. find_derived_data_dir の mtime フォールバック
**現状**: WorkspacePath が一致しない場合、最も新しい DerivedData ディレクトリを使う（85-89 行）。WARNING は出すが処理は続行する
**本質**: 間違ったプロジェクトの DerivedData を使ってビルドする可能性がある。「WARNING を出して続行」は silent wrong answer パターン。別プロジェクトのバイナリを /Applications にインストールしてしまうリスクがある
**あるべき姿**: フォールバックを削除し、WorkspacePath が一致しなければ None を返す（= ビルドが fresh start になる）。そもそも複数候補がある状況は clean build で解消されるべき

### 2. install_app の責務過多
**現状**: 1 関数（171-251 行、約 80 行）に 6 つの責務が混在:
  1. アプリの終了（177-181）
  2. .new へのコピー（191）
  3. ウィジェット存在の検証（194-206）
  4. 現行バージョンのバックアップ（208-219）
  5. アトミックスワップ（221）
  6. ウィジェットバイナリ鮮度検証（224-248）+ バンドルビット設定（251）
**本質**: 変更理由が 6 つある。ウィジェット検証ロジックの変更がインストール関数に触れる必要がある。テストも困難（副作用が多すぎてモック対象が爆発する）
**あるべき姿**: `quit_app()`, `install_app()` (コピー+スワップのみ), `verify_widget_in_bundle()`, `backup_current_app()` に分離。main() のフローで直列に呼ぶ

### 3. register_and_clean の責務混在
**現状**: 1 関数（312-347 行）に 4 つの責務:
  1. 古い LS 登録の解除（316）
  2. エンタイトルメント検証（319-336）
  3. LS 登録 + pluginkit（340-342）
  4. プロセスの kill（344-346）
**本質**: エンタイトルメント検証は「登録と清掃」ではなく「ビルド成果物の検証」。プロセス kill は「環境のリセット」。名前と内容が乖離しており、何がどこで行われるか予測できない
**あるべき姿**: `verify_entitlements()`, `register_app_and_widget()`, `restart_widget_processes()` に分離

### 4. deregister_stale_apps の二重呼び出し
**現状**: `main()` の 405 行目（ビルド前）と `register_and_clean()` の 316 行目（インストール後）で同じ `deregister_stale_apps()` が呼ばれる
**本質**: 意図的かバグか判別できない。ビルド前に DerivedData を LS から外す理由と、インストール後に外す理由は異なるはずだが、コメントで区別されていない。将来のメンテナで「これ重複では？」と一方を消して問題を起こすリスクがある
**あるべき姿**: ビルド前の deregister は「xcodebuild が正しい署名でビルドするため」、インストール後は「LS が /Applications を唯一のソースとして認識するため」。目的が異なるなら別関数名にするか、呼び出し箇所にコメントで意図を明記する

### 5. runner.py の check/allow_fail の意味論が混乱
**現状**: `run()` は `check` と `allow_fail` の 2 つのフラグを持つ（runner.py 8-28 行）。`check=False, allow_fail=False` は `allow_fail=True` と同じ動作（WARNING を出して続行）。呼び出し元では `check=False` と `allow_fail=True` が混在
**本質**: 2 つのフラグで 4 状態のうち 2 つが同じ挙動。呼び出し元が使い分けに迷う。実際 `build_and_install.py` では `check=False`（テスト・ビルドで rc を自前チェック）と `allow_fail=True`（killall 等で失敗を許容）の 2 パターンだけが必要
**あるべき姿**: `check: bool = True` の 1 フラグに統一。`check=False` なら WARNING + 続行。呼び出し元が rc を自分で見たい場合は `check=False` で十分

### 6. マジックナンバーの sleep
**現状**: `time.sleep(2)`（179, 379 行）、`time.sleep(0.5)`（181 行）、`time.sleep(3)`（347 行）が散在。なぜその秒数なのか説明がない
**本質**: タイミング依存のバグの温床。環境（マシン速度、ディスク I/O）によって不足する可能性がある。次にデプロイが不安定になったとき、sleep を疑うべきか他を疑うべきか判断材料がない
**あるべき姿**: 各 sleep に理由コメントを付ける（例: `# Wait for app to fully quit before killall`）。可能なら polling に置き換える（例: `pgrep` でプロセス消滅を確認）
