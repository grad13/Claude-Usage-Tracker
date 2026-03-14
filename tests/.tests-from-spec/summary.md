# Spec to Tests Summary

実行日: 2026-03-15

## 統計

| 項目 | 件数 |
|------|------|
| 対象spec | 7 |
| covered | 1 |
| partial | 6 |
| missing | 0 |
| 生成test | 6ファイル (57ケース) |

## Test一覧

| Test | Spec | Source | Check | Action |
|------|------|--------|-------|--------|
| tests/tools/test_runner.py | docs/spec/tools/runner.md | code/tools/lib/runner.py | covered | - |
| tests/tools/test_build_and_install_supplement2.py | docs/spec/tools/build-and-install.md | code/tools/build_and_install.py | partial | generated |
| tests/tools/test_rollback_supplement2.py | docs/spec/tools/rollback.md | code/tools/rollback.py | partial | generated |
| tests/tools/test_launchservices_supplement2.py | docs/spec/tools/launchservices.md | code/tools/lib/launchservices.py | partial | generated |
| tests/tools/test_version_supplement.py | docs/spec/tools/version.md | code/tools/lib/version.py | partial | generated |
| tests/tools/test_binary_backup_supplement.py | docs/spec/tools/db-backup.md | code/tools/build_and_install.py | partial | generated |
| tests/tools/test_data_protection_supplement2.py | docs/spec/tools/data-protection.md | code/tools/lib/data_protection.py | partial | generated |

## 生成テスト詳細

### test_build_and_install_supplement2.py (27ケース)
- run_test_gate: 成功/失敗パス
- build_app: ビルドアーティファクト検証
- verify_installed_widget: size/mtime検証
- register_and_clean: entitlements検証
- main pipeline: 状態遷移テスト
- install_app: no-existing-app, leftover cleanup

### test_rollback_supplement2.py (7ケース)
- LV-01: backup_dir非存在時のFileNotFoundError
- RB-05: .app不在時のFileNotFoundError
- RB-06: FileExistsError（移動先に既存ファイル）
- MN-01/02/03: main() CLIエントリポイント
- LaunchServices登録・アプリ起動

### test_launchservices_supplement2.py (7ケース)
- DS-06: Trash不存在時のスキップ
- DS-07: DerivedData内のファイル（非ディレクトリ）フィルタリング
- DS-08: lsregister -u 失敗時のWARNING出力と続行
- RA-02: lsregister -f 失敗時のRuntimeError
- DW-03/04: widget存在but path行なしの複合パターン
- DW-05: lsregister -dump 失敗時のNone返却

### test_version_supplement.py (4ケース)
- VR-03: 破損plist
- VR-04: CFBundleShortVersionStringキーなし
- VR-05: 予期しない例外 + stderr WARNING
- VR-06: str型パス対応

### test_binary_backup_supplement.py (6ケース)
- RO-02: thresholdによるローテーション
- RO-04: keep=0
- BD-03: DBエラー
- BD-04: テーブル不在
- CL-03: 現在DB空
- CL-04: バックアップ不正

### test_data_protection_supplement2.py (6ケース)
- PF-05: 複数ファイル保護時の部分失敗
- SF-02: ブロック内ファイル削除→.shelterから復元
- SF-03: .shelterバックアップ消失→ERROR
- SH-01: _sha256 通常ファイル直接テスト
- SH-02: _sha256 空ファイル
- RS-01: _recover_stale_backup .backupなし（no-op）
