---
Date: 2026-03-15
Scope: tests/tools/
Total files: 15 (14 test files + 1 conftest.py)
Must: 0
Should: 1
Clean: 14
---

# refactor-tests summary — tools系

## 結果一覧

| File | Lines | Judgment | Issues |
|------|-------|----------|--------|
| test_build_and_install_supplement.py | 233 | **should** | S6, S7 |
| test_deploy_gate.py | 181 | clean | — |
| test_data_protection.py | 171 | clean | — |
| test_binary_backup.py | 170 | clean | — |
| test_launchservices_supplement.py | 131 | clean | — |
| test_data_protection_supplement.py | 120 | clean | — |
| test_rollback.py | 113 | clean | — |
| test_build_and_install.py | 113 | clean | — |
| test_rollback_supplement.py | 109 | clean | — |
| test_deploy_integration.py | 94 | clean | — |
| test_runner.py | 84 | clean | — |
| test_find_derived_data.py | 82 | clean | — |
| conftest.py | 46 | clean | — |
| test_version.py | 35 | clean | — |
| test_launchservices.py | 31 | clean | — |

## should 詳細

### test_build_and_install_supplement.py (S6, S7)

→ 詳細: `tests/.refactor-tests/should/tools/test_build_and_install_supplement.py.md`

- **S6**: `data_protection.shelter_file` のテストが混入。`test_data_protection.py` に分離すべき
- **S7**: `subprocess.run` を手書き関数で差し替え。`unittest.mock.patch` + `side_effect` に統一すべき

## 補足事項（判定基準外）

- **test_build_and_install.py**: ファイル名は `build_and_install` だが、実際のテスト対象は `db_backup` モジュール（`check_lost_rows`, `rotate_backups`）。ファイル名不一致。

## 総評

tools系テストは全体的に良好。500行超のファイルはなく、ほとんどが単一責務・適切なモッキング。
対処が必要なのは `test_build_and_install_supplement.py` の1ファイルのみ（責務混在 + 手書きモック）。
