# refactor-code Summary

**Date**: 2026-03-06
**Target**: code/ (Swift 20/32ファイル分析、優先度順)
**Result**: must: 0 / should: 2 / clean: 18

## should (2 files)

| Lines | File | Issues |
|------:|------|--------|
| 320 | ClaudeUsageTracker/UsageFetcher.swift | 複数責務混在（フェッチ/パース/日付処理/JS生成）、Format A/B フォールバック、UsageResultモデル同居 |
| 308 | ClaudeUsageTracker/UsageViewModel.swift | WebView構築がViewModel内、デバッグログ埋め込み、Cookie/Session管理混在、初期化副作用過多 |

## clean (18 files)

| Lines | File |
|------:|------|
| 291 | ClaudeUsageTracker/UsageStore.swift |
| 232 | ClaudeUsageTracker/MenuContent.swift |
| 219 | ClaudeUsageTrackerWidget/WidgetMiniGraph.swift |
| 200 | ClaudeUsageTracker/UsageViewModel+Session.swift |
| 194 | ClaudeUsageTracker/Settings.swift |
| 183 | ClaudeUsageTracker/AnalysisSchemeHandler.swift |
| 149 | ClaudeUsageTracker/MiniUsageGraph.swift |
| 132 | ClaudeUsageTracker/AlertChecker.swift |
| 96 | ClaudeUsageTracker/UsageViewModel+Settings.swift |
| 94 | ClaudeUsageTrackerWidget/WidgetMediumView.swift |
| 92 | ClaudeUsageTrackerShared/SQLiteBackup.swift |
| 75 | ClaudeUsageTracker/MenuBarLabel.swift |
| 63 | ClaudeUsageTracker/LoginWindowView.swift |
| 54 | ClaudeUsageTrackerShared/SnapshotModels.swift |
| 43 | ClaudeUsageTrackerShared/DisplayHelpers.swift |
| 36 | ClaudeUsageTracker/ClaudeUsageTrackerApp.swift |
| 30 | ClaudeUsageTracker/AnalysisWindowView.swift |
| 18 | ClaudeUsageTracker/AnalysisExporter.swift |

## 未チェック (12 files — 今回の20件上限外)

| Lines | File | 前回(3/4)判定 |
|------:|------|--------------|
| 119 | ClaudeUsageTrackerShared/UsageReader.swift | - |
| 111 | ClaudeUsageTrackerShared/SQLiteHelper.swift | - |
| 109 | ClaudeUsageTracker/Protocols.swift | clean |
| 109 | ClaudeUsageTrackerWidget/WidgetLargeView.swift | clean |
| 75 | ClaudeUsageTracker/WebViewCoordinator.swift | clean |
| 73 | ClaudeUsageTrackerWidget/WidgetSmallView.swift | clean |
| 66 | ClaudeUsageTrackerWidget/UsageWidget.swift | clean |
| 41 | ClaudeUsageTracker/NotificationManager.swift | clean |
| 22 | ClaudeUsageTrackerShared/AppGroupConfig.swift | clean |
| 15 | ClaudeUsageTracker/LoginWebView.swift | clean |
| 10 | ClaudeUsageTrackerWidget/ClaudeUsageTrackerWidgetBundle.swift | clean |
| 9 | ClaudeUsageTrackerShared/ClaudeUsageTrackerShared.swift | clean |

## 前回(3/4)→今回(3/6) 変化

前回 should → 今回 clean に改善: UsageStore, MenuContent, WidgetMiniGraph, SQLiteBackup, AlertChecker, ClaudeUsageTrackerApp, AnalysisSchemeHandler, Settings (8ファイル)

---

# Refactor Analysis — code/tools/ (Python)

**Date**: 2026-03-04
**Target**: code/tools/ (全10ファイル、.venv除外)
**Result**: must: 0 / should: 1 / clean: 9

## should (1 file)

| Lines | File | Issues |
|------:|------|--------|
| 290 | tools/tests/test_data_protection.py | 責務混在 — build_and_install.py のロジックテスト(Test 1-5)と data_protection モジュールのテスト(Test 12-19)が同居 |

## clean (9 files)

| Lines | File |
|------:|------|
| 311 | tools/build_and_install.py |
| 125 | tools/rollback.py |
| 124 | tools/lib/data_protection.py |
| 69 | tools/lib/launchservices.py |
| 19 | tools/lib/version.py |
| 47 | tools/tests/conftest.py |
| 171 | tools/tests/test_binary_backup.py |
| 63 | tools/tests/test_lib_functions.py |
| 114 | tools/tests/test_rollback.py |
