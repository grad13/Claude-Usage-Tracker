# Spec to Tests Summary

実行日: 2026-03-04

## 統計

| 項目 | 件数 |
|------|------|
| 対象spec | 4 |
| covered | 0 |
| partial | 4 |
| missing | 0 |
| 生成test（追記） | 7ファイル / 41ケース |

## Test一覧

| Test | Spec | Source | Check | Action |
|------|------|--------|-------|--------|
| meta/WebViewCoordinatorSupplementTests.swift | meta/webview-coordinator.md | code/ClaudeUsageTracker/WebViewCoordinator.swift | partial | generated |
| meta/ProtocolsSupplementTests2.swift | meta/protocols.md | code/ClaudeUsageTracker/Protocols.swift | partial | generated |
| analysis/AnalysisSchemeHandlerSupplementTests2.swift | analysis/analysis-scheme-handler.md | code/ClaudeUsageTracker/AnalysisSchemeHandler.swift | partial | generated |
| tools/test_launchservices_supplement.py | tools/build-and-install.md | code/tools/lib/launchservices.py | partial | generated |
| tools/test_data_protection_supplement.py | tools/build-and-install.md | code/tools/lib/data_protection.py | partial | generated |
| tools/test_build_and_install_supplement.py | tools/build-and-install.md | code/tools/build_and_install.py | partial | generated |
| tools/test_rollback_supplement.py | tools/build-and-install.md | code/tools/rollback.py | partial | generated |

## 生成内容（前回分: Swift）

### 1. WebViewCoordinatorSupplementTests.swift（7ケース）

| Specシナリオ | テストメソッド |
|-------------|--------------|
| didFinish viewModel==nil → return | testDidFinish_viewModelNil_doesNotCallAnyDelegateMethod |
| didFinish popup → checkPopupLogin() | testDidFinish_popupWebView_callsCheckPopupLogin, testDidFinish_popupWebView_doesNotCallHandlePageReady |
| didFinish main+claude.ai → handlePageReady() | testDidFinish_mainWebView_hostClaudeAI_callsHandlePageReady, testDidFinish_mainWebView_hostClaudeAI_doesNotCallCheckPopupLogin |
| didFinish main+非claude.ai → skip | testDidFinish_mainWebView_hostNotClaudeAI_doesNotCallHandlePageReady, testDidFinish_mainWebView_urlNil_doesNotCallHandlePageReady |

### 2. ProtocolsSupplementTests2.swift（14ケース）

| Case ID | テストメソッド |
|---------|--------------|
| DI-03 | test_defaultSnapshotWriter_isAssignableToSnapshotWriting, test_defaultSnapshotWriter_conformsToSnapshotWriting |
| DI-04 | test_defaultUsageFetcher_isAssignableToUsageFetching, test_defaultUsageFetcher_conformsToUsageFetching |
| DI-05 | test_defaultWidgetReloader_isAssignableToWidgetReloading, test_defaultWidgetReloader_conformsToWidgetReloading |
| DI-06 | test_defaultLoginItemManager_isAssignableToLoginItemManaging, test_defaultLoginItemManager_conformsToLoginItemManaging |
| DI-08 | test_defaultAlertChecker_isAssignableToAlertChecking, test_defaultAlertChecker_conformsToAlertChecking |
| EX-01 | test_setEnabled_true_throwsOnFailure, test_setEnabled_true_doesNotThrowOnSuccess |
| EX-02 | test_setEnabled_false_throwsOnFailure, test_setEnabled_false_doesNotThrowOnSuccess |

### 3. AnalysisSchemeHandlerSupplementTests2.swift（4ケース）

| Case ID | テストメソッド |
|---------|--------------|
| UT-05 | testStart_nilURL_returns400WithMissingURLBody |
| UT-09 | testStart_usageDb_noTables_returnEmptyJsonArray |
| UT-14 | testStart_tokensDb_noTables_returnEmptyJsonArray |
| UT-20 | testStart_serializeFailure_returns500 |

## 生成内容（今回: Python/pytest — tools系）

### 4. test_launchservices_supplement.py（5ケース）

| テスト番号 | テスト関数 | 検証内容 |
|-----------|-----------|---------|
| Test 23 | test_deregister_stale_apps_derived_data | DerivedData 内アプリの lsregister -u 呼び出し |
| Test 24 | test_deregister_stale_apps_trash | Trash 内アプリの lsregister -u 呼び出し |
| Test 25 | test_register_app | lsregister -f 呼び出し |
| Test 26 | test_dump_widget_registration_found | ウィジェット発見時のパス返却 |
| Test 27 | test_dump_widget_registration_not_found | ウィジェット未発見時の None 返却 |

### 5. test_data_protection_supplement.py（5ケース）

| テスト番号 | テスト関数 | 検証内容 |
|-----------|-----------|---------|
| Test 28 | test_restore_if_changed_returns_0_unchanged | 未変更 → 戻り値 0 |
| Test 29 | test_restore_if_changed_returns_1_corrupted | 改変 → 戻り値 1 + リストア |
| Test 30 | test_restore_if_changed_returns_2_deleted | 削除 → 戻り値 2 + リストア |
| Test 31 | test_restore_if_changed_returns_0_skipped | hash_before=None → 戻り値 0 |
| Test 32 | test_snapshot_raises_on_copy_failure | cp 失敗 → OSError (Layer 3) |

### 6. test_build_and_install_supplement.py（3ケース）

| テスト番号 | テスト関数 | 検証内容 |
|-----------|-----------|---------|
| Test 33 | test_backup_database_creates_backup | バックアップ作成 + 行数カウント返却 |
| Test 34 | test_backup_database_db_not_found | DB未存在 → (0, None) |
| Test 35 | test_backup_database_rotation | バックアップ12個 → 10個にローテーション |

### 7. test_rollback_supplement.py（3ケース）

| テスト番号 | テスト関数 | 検証内容 |
|-----------|-----------|---------|
| Test 36 | test_rollback_permission_denied | 書き込み権限なし → RuntimeError |
| Test 37 | test_rollback_cleans_leftover_new | .new 残骸のクリーンアップ |
| Test 38 | test_rollback_cleans_leftover_removing | .removing 残骸のクリーンアップ |
