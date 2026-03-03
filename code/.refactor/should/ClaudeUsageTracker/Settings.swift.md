---
File: ClaudeUsageTracker/Settings.swift
Lines: 183
Judgment: should
Issues: [Validation logic mixed into data model, Dual fallback strategies]
---

# Settings.swift

## 問題点

### 1. AppSettings に検証ロジックが混在

**現状**: `AppSettings` struct が単なるデータモデルではなく、`validated()` メソッド（行95-107）で値の正規化処理を行っている。threshold のクランプ、refreshIntervalMinutes の負値チェック、chartWidth の範囲チェックなど、ビジネスロジックが混在している。

**本質**: `AppSettings` は「設定データの表現」と「設定値の正当性確保」という2つの責務を持っている。設定値が不正だった場合の修正が UI層やVM層ではなくデータモデル層で起きている。テスト時に validation が implicit に走るため、何が正規化されたのか追跡しづらい。

**あるべき姿**: `AppSettings` は純粋なデータ構造。validation は別の責務（例えば `SettingsValidator` や、ViewModel が `settings.validated()` を明示的に呼び出す）として分離。validation が常に走るのではなく、必要な箇所で明示的に呼び出される。

### 2. デフォルト値の重複生成（Fallback 戦略の分散）

**現状**:
- `init(from decoder:)` 内：`AppSettings()` を呼んで各フィールドのデフォルトを取得（行74, 81-89）
- `validated()` 内：`AppSettings()` を再度呼んで不正値時のデフォルトを取得（行98, 101）
- SettingsStore 内：new defaults を作成（行149）

デフォルト値の"源"が複数の場所に分散している。

**本質**: デフォルト値の定義がハードコードされているため、デフォルト値を変更する際に複数箇所の修正が必要。また、`AppSettings()` を呼ぶたびに新しいインスタンスが生成されるため、デフォルト値の一貫性が暗黙的に依存している。

**あるべき姿**: デフォルト値を1箇所に集約。例えば `static let defaults: AppSettings` を定義して、`init(from:)` と `validated()` がそれを参照する形に統一。もしくは `static` メソッドで個別フィールドのデフォルト値を取得。

