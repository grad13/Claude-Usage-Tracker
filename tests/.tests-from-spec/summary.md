# Spec to Tests Summary

実行日: 2026-03-06

## 統計

| 項目 | 件数 |
|------|------|
| 対象spec | 17 |
| covered | 6 |
| partial | 11 |
| missing | 0 |
| partial (テスト生成) | 4 |
| partial (ユニットテスト範囲外) | 7 |
| 生成test（新規+追記） | 4ファイル / 30ケース |

## Test一覧

| Test | Spec | Source | Check | Action | 備考 |
|------|------|--------|-------|--------|------|
| meta/ArchitectureViewModelStateTests.swift | meta/architecture.md | ClaudeUsageTrackerApp.swift 他 | partial | - | ユニットテスト範囲外 (後述) |
| meta/ViewModelTests.swift 他 | meta/viewmodel-lifecycle.md | UsageViewModel.swift 他 | covered | - | - |
| meta/ViewModelSessionTests.swift | meta/viewmodel-session.md | UsageViewModel+Session.swift | covered | - | - |
| meta/WebViewCoordinatorTests.swift 他 | meta/webview-coordinator.md | WebViewCoordinator.swift | covered | - | - |
| meta/ProtocolsSupplementTests3.swift | meta/protocols.md | Protocols.swift | partial | generated | DI-09, DI-10 (4ケース) |
| data/SettingsTests.swift 他 | data/settings.md | Settings.swift 他 | covered | - | - |
| data/FetcherTests.swift 他 | data/usage-fetcher.md | UsageFetcher.swift | partial | - | ユニットテスト範囲外 (後述) |
| data/UsageStoreTests.swift 他 | data/usage-store.md | UsageStore.swift | covered | - | - |
| data/AlertCheckerTests.swift 他 | data/alert.md | AlertChecker.swift 他 | partial | - | ユニットテスト範囲外 (後述) |
| ui/AppWindowsSupplementTests.swift | ui/app-windows.md | ClaudeUsageTrackerApp.swift | partial | - | ユニットテスト範囲外 (後述) |
| ui/MenuContentSupplementTests.swift | ui/menu-content.md | MenuContent.swift | partial | - | ユニットテスト範囲外 (後述) |
| ui/MiniUsageGraphLogicTests.swift | ui/mini-usage-graph.md | MiniUsageGraph.swift | partial | generated | UV-01~06, FE-01~03 (10ケース) |
| - | analysis/overview.md | AnalysisExporter.swift | covered | - | 子specでカバー |
| analysis/AnalysisSchemeHandlerMetaJSONSupplementTests.swift | analysis/analysis-scheme-handler.md | AnalysisSchemeHandler.swift | partial | generated | UT-M06~M10 (5ケース) |
| analysis/AnalysisExporterJSLogicTests.swift | analysis/analysis-exporter.md | AnalysisExporter.swift (JS) | partial | generated | BW/BH/MN 11ケース |
| widget/WidgetMiniGraphCalcTests.swift 他 | widget/design.md | UsageWidget.swift 他 | partial | - | ユニットテスト範囲外 (後述) |
| tools/test_*.py | tools/build-and-install.md | build_and_install.py 他 | partial | - | ユニットテスト範囲外 (後述) |

## 生成内容

### 1. ProtocolsSupplementTests3.swift (4ケース)

| Case ID | テストメソッド | 検証内容 |
|---------|--------------|---------|
| DI-09 | test_defaultNotificationSender_conformsToNotificationSending | `is` check |
| DI-09 | test_defaultNotificationSender_isAssignableToNotificationSending | `any` assignability |
| DI-10 | test_usageViewModel_conformsToWebViewCoordinatorDelegate | `is` check (@MainActor) |
| DI-10 | test_usageViewModel_isAssignableToWebViewCoordinatorDelegate | `any` assignability (@MainActor) |

DI-03 (SnapshotWriting): specから削除済み（UsageReader が usage.db を直接読む方式に変更済み）
DI-07 (TokenSyncing): specから削除済み（機能omit済み）

### 2. AnalysisSchemeHandlerMetaJSONSupplementTests.swift (5ケース)

| Case ID | テストメソッド | 検証内容 |
|---------|--------------|---------|
| UT-M06 | testMetaJson_usageAndSessions_returnsSessionArrays | usage_log+sessions有 → arrays出力 |
| UT-M07 | testMetaJson_usageDataNoSessions_returnsEmptySessionArrays | usage有+sessions空 → empty arrays |
| UT-M08 | testMetaJson_noUsageButSessions_returnsSessionArraysOnly | usage空+sessions有 → sessionsのみ |
| UT-M09 | testMetaJson_allEmpty_returnsEmptyObject | 全空 → {} |
| UT-M10 | testMetaJson_sessionNullKeys_omittedFromObject | NULL → キー省略 |

### 3. AnalysisExporterJSLogicTests.swift (11ケース)

| Case ID | テストメソッド | 検証内容 |
|---------|--------------|---------|
| BW-01 | testBW01_singleSession_groupedTogether | 単一session、zero point追加 |
| BW-02 | testBW02_twoSessions_splitByResetsAt | resets_at変更で2 session |
| BW-03 | testBW03_weeklyPercentNull_rowSkipped | weekly_percent null → skip |
| BW-04 | testBW04_resetsAtNull_rowSkipped | weekly_resets_at null → skip |
| BW-05 | testBW05_emptyData_emptySessions | 空配列 → 空sessions |
| BH-01 | testBH01_singleSession_zeroPointAppended | zero point at resets_at |
| BH-02 | testBH02_hourlyPercentNull_rowSkipped | hourly_percent null → skip |
| BH-03 | testBH03_resetsAtNull_rowSkipped | idle period → skip |
| BH-04 | testBH04_twoSessions_splitByResetsAt | session split |
| MN-01 | testMN01_hundredRecords_chartCreated | 100レコード → チャート作成 |
| MN-02 | testMN02_zeroRecords_chartCreatedEmpty | 0レコード → 空チャート |

**Spec↔Code乖離の発見**: specで定義されていた `insertResetPoints`, `isGapSegment`, `formatMin` はコードに存在しない。リセットポイント挿入は `buildWeeklySessions`/`buildHourlySessions` 内にインライン実装。ギャップスライダー機能は未実装。spec要更新。

### 4. MiniUsageGraphLogicTests.swift (10ケース)

| Case ID | テストメソッド | 検証内容 |
|---------|--------------|---------|
| UV-01 | testUV01_exactlyFiveHours_returnsFiveHourPercent | 5h window → fiveHourPercent |
| UV-02 | testUV02_thresholdBoundary_returnsFiveHourPercent | 5h+1s → fiveHourPercent |
| UV-03 | testUV03_aboveThreshold_returnsSevenDayPercent | 5h+2s → sevenDayPercent |
| UV-04 | testUV04_sevenDayWindow_returnsSevenDayPercent | 7d → sevenDayPercent |
| UV-05 | testUV05_fiveHourNil_returnsNil | fiveHour nil → nil |
| UV-06 | testUV06_sevenDayNil_returnsNil | sevenDay nil → nil |
| FE-01 | testFE01_resetsAtSet_extendsToResetTime | resetFrac > lastPoint → resetFrac |
| FE-01b | testFE01b_resetsAtBeforeLastPoint_usesLastPointFrac | resetFrac < lastPoint → lastPoint |
| FE-02 | testFE02_noResets_nowBeyondLastPoint_usesNowFrac | nowFrac > lastPoint → nowFrac |
| FE-03 | testFE03_noResets_nowBeforeLastPoint_usesLastPointFrac | nowFrac < lastPoint → lastPoint |

コード変更: `usageValue` を `private` → `internal` に変更、`fillEndFrac` メソッドを抽出（Canvas body のインラインロジックから）。

## ユニットテスト範囲外の不足分と推奨テスト手法

### カテゴリA: WKWebView結合テスト

| Spec | 不足内容 | 推奨手法 |
|------|---------|---------|
| architecture.md | Org ID JS fallback, OAuth popup | WKWebView + evalJS (AnalysisJSTestCase 方式) |
| usage-fetcher.md | readOrgId, hasValidSession, fetch | protocol抽象化リファクタリング → mock injection。または WKWebView結合テスト |

### カテゴリB: SwiftUI View テスト

| Spec | 不足内容 | 推奨手法 |
|------|---------|---------|
| app-windows.md | Window定義, AppDelegate, LoginWindowView | XCUITest (UI自動テスト) |
| menu-content.md | ボタンアクション, トグル, Quit | XCUITest (メニュー操作) |
| widget/design.md | SwiftUI View, WidgetKit runtime | XCUITest (ウィジェットプレビュー) |

### カテゴリC: OS API 結合テスト

| Spec | 不足内容 | 推奨手法 |
|------|---------|---------|
| alert.md | NI-01, requestAuthorization, send | protocol mock は既存。実機テストで通知表示を確認 |

### カテゴリD: E2E テスト

| Spec | 不足内容 | 推奨手法 |
|------|---------|---------|
| tools/build-and-install.md | E2Eフロー | サンドボックス環境での pytest E2E |

### 優先度まとめ

| 優先度 | 対処 | 効果 |
|--------|------|------|
| 高 | protocols.md spec修正: DI-03削除、DI-07削除 | spec↔code乖離の解消（完了済み） |
| 高 | mini-usage-graph: ロジック抽出 → ユニットテスト化 | 10ケース追加（完了済み） |
| 高 | analysis-exporter.md spec修正: insertResetPoints/isGapSegment/formatMin → 実コードに合わせて更新 | spec↔code乖離の解消（要対応） |
| 中 | XCUITest ターゲット追加 → menu-content, app-windows | SwiftUI操作の自動テスト |
| 中 | usage-fetcher: readOrgId protocol抽出 | WKWebView依存の分離 |
| 低 | tools E2E pytest | CI でのみ意味がある |
| 低 | alert 実機テスト | mock で十分カバー済み |
