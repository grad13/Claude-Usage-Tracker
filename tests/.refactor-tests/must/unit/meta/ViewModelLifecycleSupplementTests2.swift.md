---
File: tests/ClaudeUsageTrackerTests/meta/ViewModelLifecycleSupplementTests2.swift
Lines: 535
Judgment: must
Issues: [M2]
---

# ViewModelLifecycleSupplementTests2.swift

## 問題点

### 1. [M2] 500行超の大型テストファイル

**現状**: 535行に5つのテストクラス（ViewModelHandlePageReadyTests, ViewModelCanRedirectTests, ViewModelIsOnUsagePageTests, ViewModelFetchSilentlyRetryTests, ViewModelDebugLoggingTests, ViewModelSettingsWidgetReloaderTests）が同居している。
**本質**: 1ファイルに多数のテストクラスが詰め込まれており、各クラスの責務境界が曖昧になっている。handlePageReady決定テーブル、canRedirectクールダウン、isOnUsagePage、fetchSilentlyリトライ、debugログ、設定変更時のwidgetReloader副作用と、テスト対象の関心事が6つに分かれている。
**あるべき姿**: 関心事ごとにファイルを分割する。例: HandlePageReadyTests.swift、CanRedirectTests.swift、FetchSilentlyTests.swift、DebugLoggingTests.swift、SettingsWidgetReloaderTests.swift。各ファイルが単一の関心事に集中し、setUp/makeVMの重複も解消できる。
