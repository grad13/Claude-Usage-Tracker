---
File: tests/ClaudeUsageTrackerTests/ui/MenuContentSupplementTests.swift
Lines: 484
Judgment: should
Issues: [S6]
---
# MenuContentSupplementTests.swift

## 問題点

### 1. [S6] 複数モジュールを1ファイルでテスト

**現状**: 1つのテストクラスで UsageViewModel のプロパティ確認(40-205行)、AppSettings のプリセット定数・デフォルト値(212-401行)、ChartColorPreset の displayName(315-347行)、DailyAlertDefinition の allCases(471-483行) をテストしている。これらは独立した4つのモジュールに属する。

**本質**: テスト対象が「MenuContent が依存するもの全部」という UI 起点のグルーピングになっており、モジュール境界と一致していない。AppSettings.presets や ChartColorPreset.displayName は MenuContent 固有ではなく、他の箇所からも参照されうる共通モデル層の仕様である。変更時にどのテストファイルを見ればよいか分からなくなる。

**あるべき姿**: テスト対象モジュールごとにファイルを分離する。ViewModel のプロパティ表示条件は ViewModel テストに、AppSettings のプリセット定数は Settings テストに、ChartColorPreset/DailyAlertDefinition は各モデルのテストに配置する。
