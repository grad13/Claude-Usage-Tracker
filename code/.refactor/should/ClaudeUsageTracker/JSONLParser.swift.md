---
File: ClaudeUsageTracker/JSONLParser.swift
Lines: 137
Judgment: should
Issues: [mixed-responsibilities, silent-failures, brittle-json-extraction, untestable-static-methods]
---

# JSONLParser.swift

## 問題点

### 1. 責務混在: 解析 + 重複排除

**現状**: `parseDirectory`, `parseLines`, `parseFile` が全て `deduplicate()` を呼び出している（56行、66行目）。解析と重複排除が同一モジュールに密結合

**本質**:
- 重複排除ロジックは解析とは独立した「データ品質」の責務
- 将来、解析結果をそのまま必要とするケース（監査ログなど）が出ると、重複排除をスキップできない
- 重複排除戦略（requestId ベース）が変わると、パーサー全体に影響

**あるべき姿**:
- パーサーは「JSONL → TokenRecord[]」に徹する
- 重複排除は呼び出し側で明示的に行う（`JSONLParser.parse() -> Deduplicator.deduplicate()` など）

### 2. サイレント失敗: エラー情報なし

**現状**:
- 行 91: 不正な JSON → `nil` で静かに破棄
- 行 117: タイムスタンプ解析失敗 → `nil` で静かに破棄
- 統計情報なし（何行処理、何行失敗、失敗理由）

**本質**:
- デバッグが困難（なぜレコードが足りないのか原因不明）
- ログなしでは本番環境での問題追跡が不可能
- JSONL スキーマの変化を検知できない

**あるべき姿**:
- 失敗の詳細をログに記録（ファイルパス、行番号、失敗理由）
- オプションで統計情報を返す（解析:✓/✗、理由別集計など）

### 3. 脆弱な JSON 抽出

**現状**:
```swift
guard json["type"] as? String == "assistant" else { return nil }
guard let requestId = json["requestId"] as? String else { return nil }
guard let message = json["message"] as? [String: Any] else { return nil }
guard let usage = message["usage"] as? [String: Any] else { return nil }
// ...
webSearchRequests: (usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int ?? 0
```

複数の無名の guard を連鎖させ、不正なキー名に気づきにくい

**本質**:
- スキーマが変わると複数箇所を修正が必要
- ネストが深い構造（`message.usage.server_tool_use.web_search_requests`）で、一つのパスが変わると全体が壊れる
- JSONSerialization は型安全性がない → 実行時エラー

**あるべき姿**:
- `Codable` 構造体でスキーマを定義（`APIResponse`, `UsageData` など）
- スキーマ変更は一箇所（構造体定義）に局所化
- 失敗理由が明確（`missingField`, `typeMismatch` など）

### 4. テスト不可能: 静的メソッド

**現状**: `enum JSONLParser` で全メソッドが `static`

**本質**:
- ファイル I/O をモック化できない
- JSONL 形式の変化に対応するテストが書きづらい
- 依存関係注入ができない

**あるべき姿**:
- パーサーをクラスまたは struct で提供（依存性注入可能）
- `FileManager` を protocol に変更可能にする
- テスト時は in-memory JSON を直接渡せるようにする
