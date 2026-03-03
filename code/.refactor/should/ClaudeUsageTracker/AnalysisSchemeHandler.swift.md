---
File: ClaudeUsageTracker/AnalysisSchemeHandler.swift
Lines: 235
Judgment: should
Issues: [Responsibility mixing, Silent fallback on query failures, Parameter type safety, Query isolation]
---

# AnalysisSchemeHandler.swift

## 問題点

### 1. 責務の混在：WKURLSchemeHandler と SQLite Query Handler

**現状**:
- `AnalysisSchemeHandler` が単一クラスで以下を担当している:
  - WKURLSchemeHandler のプロトコル実装（行24-49）
  - 3つの異なるSQLiteクエリの実装（行53-135）
  - HTTP レスポンス生成（行206-233）

**本質**:
- Routing（URL path → 適切なクエリへの分岐）と Data Fetching（SQLiteクエリ実行）が同一クラスで混在
- テーブル構造の変更時にこのクラスのみ修正が必要
- テスト時にWKWebViewのmockが必須

**あるべき姿**:
```
AnalysisSchemeHandler: WKURLSchemeHandler のみ
  ↓ delegates to
UsageDataRepository (or UsageService)
  - queryUsageJSON()
  - queryTokensJSON()
  - queryMetaJSON()

TokensDataRepository
  - queryTokensJSON()
```

### 2. Silent Fallback on Query Failures

**現状**:
- Line 55: `guard sqlite3_open_v2(...) == SQLITE_OK else { return "[]".data(...) }`
- Line 97: `guard sqlite3_open_v2(...) == SQLITE_OK else { return "[]".data(...) }`
- Line 139: `guard sqlite3_open_v2(...) == SQLITE_OK else { return "{}".data(...) }`
- Line 114, 148: prepare_v2 失敗時も同様に空配列/空オブジェクトを返す

**本質**:
- データベース接続/クエリ失敗を UI に通知できない
- ユーザーが "データがない" と "エラーが発生した" を区別できない
- デバッグが困難（errors are swallowed）

**あるべき姿**:
- SQLiteError を定義し throw する
- WKURLSchemeTask.didFailWithError() で通知
- または HTTP 500 error を返す

### 3. Parameter Type Safety: from/to の型不一致

**現状**:
- Line 32-33: `from`, `to` を URL Query String から String で取得
- Line 68: queryUsageJSON では Int64 に parse（`Int64(from)`）
- Line 107-109: queryTokensJSON では String のまま bind（型チェックなし）

```swift
// Line 108-109: from/to が String のままバインド
for (i, value) in bindings.enumerated() {
    sqlite3_bind_text(stmt, Int32(i + 1), (value as NSString).utf8String, -1, nil)
}
```

**本質**:
- `from` が "invalid" 等の非数値で使用される場合、queryUsageJSON は無視（=無条件返却）、queryTokensJSON も無視（=全行返却）
- 両クエリが同じパラメータなのに異なる型安全性で扱われている

**あるべき姿**:
```swift
struct DateRangeFilter {
    let from: Int64?
    let to: Int64?

    init?(from: String?, to: String?) {
        if let f = from, let fv = Int64(f) {
            self.from = fv
        } else {
            self.from = nil
        }
        // ...
    }
}
```

### 4. Query Isolation Lack: 複数クエリの重複コード

**現状**:
- queryUsageJSON (Line 53-93) と queryTokensJSON (Line 95-135):
  - 両者ともに同一パターン: open → prepare → bind → step loop → finalize
  - SQL テンプレート内にカラム選択が硬コード化
  - いずれかのテーブル構造変更時に修正箇所が複数

**本質**:
- テーブル構造の変更時に修正箇所が散在
- 新しいクエリ追加時にボイラープレートを繰り返す
- テスト時に各クエリを個別にmockしにくい

**あるべき姿**:
```swift
protocol SQLiteQuery {
    associatedtype Output
    func execute(db: OpaquePointer?) -> Output?
}

struct UsageQuery: SQLiteQuery {
    let from: Int64?
    let to: Int64?

    func execute(db: OpaquePointer?) -> [[String: Any?]]? {
        // queryUsageJSON の実装をここに移動
    }
}
```
