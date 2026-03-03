---
File: ClaudeUsageTracker/UsageFetcher.swift
Lines: 328
Judgment: should
Issues: [責務混在（OrgID抽出+API呼び出し+JSON解析+セッション検証+日付解析）, フォールバック複雑化, レガシー日付解析保持]
---

# UsageFetcher.swift

## 問題点

### 1. 複数責務の混在（Org ID → API → JSON → Date解析）

**現状**:
- `fetch()` → `parse()` → `parsePercent()` → `calcPercent()` → `parseResetsAt()` → `parseResetDate()` と責務が連鎖
- Org ID抽出は JS script 内に隠蔽（228行のusageScript）、別途 `readOrgId()` メソッド存在で重複
- JSON解析（Format A/B の分岐, line 110-118）とデータ抽出（line 120-132）が同一メソッド内

**本質**:
- 責務が深くネストされており、ユニットテストで個別責務の検証が困難
- Org ID抽出ロジックが JS と Swift に分散（line 49-63 vs line 156-227）
- 新しいAPI形式対応時に `parse()` メソッド全体を修正する羽目になる

**あるべき姿**:
- 責務を分離: `OrgIdExtractor`, `UsageAPIClient`, `UsageResponseParser` に分割
- Org ID抽出は JS と Swift どちらか一方に統一（推奨: JS内で完結、Swift は readOrgId() を削除）
- JSON解析は形式判定 → データ抽出 で段階化

---

### 2. 日付解析の複雑なフォールバック（レガシー対応）

**現状**:
- `parseResetDate()` (line 289-302) で3段階のパーサー試行
- `trimFractionalSeconds()` (line 304-314) で手動の秒小数部カット
- `formatterWithFractional` と `formatterNoFractional` の2種類フォーマッター保持

**本質**:
- API レスポンス形式が変更されたが、古い形式対応コードが残存
- `parseResetsAt()` (line 267-274) で Unix timestamp と ISO 8601 両対応しているが、どちらが本来の形式か不明確
- 秒小数部のカットロジックが複雑で、なぜこれが必要なのか（どのAPI形式のためか）が不透明

**あるべき姿**:
- API形式を確定後、不要な フォールバック段階を削除
- 秒小数部の問題が本当にAPI から来ているのか確認（テスト データで検証）
- ISO 8601 パーサーは標準の `ISO8601DateFormatter` のみで十分か検証、カスタム処理が必要な根拠を記述

---

### 3. JSON 形式の二律背反（Format A vs B）

**現状**:
- Format A: `{"five_hour": {"utilization": 25, ...}}` (line 106)
- Format B: `{"windows": {"5h": {"limit": N, "remaining": N, ...}}}` (line 107)
- `parse()` で両形式を条件分岐で処理（line 110-118）

**本質**:
- どの形式が現行APIなのか、どちらが古い形式なのか、ドキュメント上では「documented」と曖昧
- `parsePercent()` (line 245-253) で Format A は utilization, Format B は limit/remaining を使い分けているが、他の数値フィールド（limit, remaining）の処理が混在
- 新しいAPI形式が追加されると、条件分岐がさらに複雑化

**あるべき姿**:
- 実際のAPIドキュメント確認後、サポート形式を明示（古い形式のサポート終了予定日など）
- Format A/B の解析ロジックを個別クラスに分離（Strategy パターン）
- `parse()` は形式判定のみに職責を限定

---

### 4. テスト可能性の低さ（WebView 依存が深い）

**現状**:
- `readOrgId(webView:)` (line 49-63) が async で WKWebView に依存
- `hasValidSession(webView:)` (line 138-152) も同様に WebView 依存
- `fetch(webView:)` (line 68-88) は webView を通じて JS 実行し、JS 内で Org ID も取得（重複）

**本質**:
- Org ID 取得と API fetch が WebView 経由で行われ、単体テストでモック化が困難
- webView のライフサイクル（準備完了、キャッシュクリア、セッション失効）の影響を受けやすい

**あるべき姿**:
- Org ID 取得 → API fetch → JSON解析 を分離し、JSON解析は WebView 非依存にする（既に `parse()` は実装済み）
- Org ID 取得は webView に依存させつつ、API fetch は URLSession ベースのクライアントに分離
- セッション検証は WebView 状態確認から独立したロジックに（例: API エラー応答で判定）

---

## まとめ

**優先度**:
1. JSON解析ロジックの形式別分離（Format A/B）→ テスト可能性向上
2. 日付解析フォールバックの整理（どの段階が必要か確認）
3. Org ID抽出の統一（JS か Swift か） → 単体テスト化
4. APIクライアントの分離（WebView 非依存化） → 再利用性向上

**リスク**:
- Org ID 抽出をJS内に統一すると、Swift 側の `readOrgId()` の動作仕様が変わる（既存利用箇所確認必須）
- 古い API 形式のサポート終了判定を誤ると、本番で解析失敗が発生
