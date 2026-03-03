---
File: ClaudeUsageTracker/AlertChecker.swift
Lines: 133
Judgment: should
Issues: [Code duplication in alert methods, Unnecessary fallback wrapper]
---
# AlertChecker.swift

## 問題点

### 1. 3つのアラート方式で重複したロジック

**現状**: `checkWeeklyAlert()` (40-56行), `checkHourlyAlert()` (60-76行), `checkDailyAlert()` (80-116行) が同じパターンを繰り返している:
- 設定の有効性チェック
- パーセント・リセット時刻の取得
- 残量計算（100.0 - percent）
- 重複通知防止チェック
- 状態更新
- 非同期通知送信

**本質**: 同一の手続きロジックが3箇所にハードコードされているため、変更時の保守コストが高く、不具合の可一貫性リスクが高い。

**あるべき姿**: 重複ロジックを抽出して単一の責務を持つヘルパーメソッドに統合。各アラート方式は「パラメータを変えて同じロジックを実行する」という宣言的な形に整理。

### 2. 不要なフォールバックパターン（DefaultAlertChecker）

**現状**: `DefaultAlertChecker` struct (128-132行) は `AlertChecking` プロトコルを実装しているが、単に `AlertChecker.shared.checkAlerts()` にデリゲートしているだけ:
```swift
struct DefaultAlertChecker: AlertChecking {
    func checkAlerts(result: UsageResult, settings: AppSettings) {
        AlertChecker.shared.checkAlerts(result: result, settings: settings)
    }
}
```

**本質**:
1. 実装がシングルトンへの単純な委譲なので、値型（struct）で包む必要がない
2. コード上「デフォルト」と呼ばれているが、実際には唯一の実装であり、他の選択肢がない
3. 概念的混乱: インターフェース実装として提供されるが、実際の使用箇所ではシングルトンの使用が支配的な可能性が高い

**あるべき姿**:
- シングルトン `AlertChecker` を直接プロトコル準拠させるか
- または、複数の実装パターンが実際に存在する場合のみ、`DefaultAlertChecker` のような適応的な実装を提供する
- 現在は単なるパススルーに過ぎないため削除またはリファクタリング推奨
