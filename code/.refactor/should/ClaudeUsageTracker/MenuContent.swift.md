---
File: ClaudeUsageTracker/MenuContent.swift
Lines: 233
Judgment: should
Issues: ["Mixed presentation and imperative dialog logic", "Business logic embedded in helper function"]
---

# MenuContent.swift

## 問題点

### 1. 宣言的なSwiftUIコンポーネントと命令型のNSAlert/NSTextFieldロジックの混在

**現状**: MenuContent は SwiftUI の View struct として宣言的に UI を構成していますが（lines 6-211）、一方で `promptCustomInterval` 関数（lines 215-232）は NSAlert と NSTextField を命令型スタイルで直接操作しており、ユーザー入力の検証やコールバック処理を含んでいます。

**本質**: SwiftUI のコンポーネントと AppKit の命令型 API が同じファイル内で混在しており、責務が一貫していません。また、`promptCustomInterval` はダイアログ表示、入力検証、コールバック実行という複数の責務を担っており、テスト困難で再利用しにくい設計になっています。

**あるべき姿**: ダイアログ表示と入力検証ロジックを専用の ViewController または AlertPresenter ヘルパーに分離し、MenuContent は純粋にメニュー項目の View 構成に専念すべきです。あるいは、SwiftUI の環境変数や DependencyInjection パターンを使ってダイアログ表示を外部化すべきです。

### 2. プリセット値（threshold、minutes）のハードコード

**現状**: Alert Settings メニュー内で `ForEach([10, 20, 30, 50], id: \.self)` や `ForEach([10, 15, 20, 30], id: \.self)` といったプリセット値がハードコードされています（lines 114, 129, 146）。また、Refresh Interval メニュー（lines 176）では `AppSettings.presets` を参照していますが、Alert Settings ではプリセットが直接埋め込まれています。

**本質**: 同じ種類のプリセット（threshold values）が複数箇所で異なる形式でハードコードされているため、一貫性がなく、保守時に同期が取りにくいです。

**あるべき姿**: すべてのプリセット値を `AppSettings` に集約し（例: `AppSettings.weeklyThresholdPresets`, `AppSettings.hourlyThresholdPresets`, `AppSettings.dailyThresholdPresets`）、MenuContent 内では参照のみを行うべきです。
