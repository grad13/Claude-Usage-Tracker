# Spec to Tests Summary

実行日: 2026-03-04

## 統計

| 項目 | 件数 |
|------|------|
| 対象spec | 3 |
| covered | 0 |
| partial | 3 |
| missing | 0 |
| 生成test（追記） | 3ファイル / 25ケース |

## Test一覧

| Test | Spec | Source | Check | Action |
|------|------|--------|-------|--------|
| meta/WebViewCoordinatorSupplementTests.swift | meta/webview-coordinator.md | code/ClaudeUsageTracker/WebViewCoordinator.swift | partial | generated |
| meta/ProtocolsSupplementTests2.swift | meta/protocols.md | code/ClaudeUsageTracker/Protocols.swift | partial | generated |
| analysis/AnalysisSchemeHandlerSupplementTests2.swift | analysis/analysis-scheme-handler.md | code/ClaudeUsageTracker/AnalysisSchemeHandler.swift | partial | generated |

## 生成内容

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
