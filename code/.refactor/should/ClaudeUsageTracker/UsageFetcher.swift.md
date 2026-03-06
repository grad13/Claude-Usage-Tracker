---
File: ClaudeUsageTracker/UsageFetcher.swift
Lines: 282
Judgment: should
Issues: [org ID取得ロジックの重複フォールバック, readOrgIdの未使用疑い]
---

# UsageFetcher.swift

## 問題点

### 1. Org ID 取得ロジックがSwift側とJS側で重複している

**現状**: `readOrgId`(L10-24)はSwift cookie store + JS `document.cookie` の2段階フォールバック。一方 `usageScript`(L110-181)のJS内にも4段階フォールバック(document.cookie, performance API, HTML content, /api/organizations)が独立して存在する。
**本質**: `fetch()`は`usageScript`を直接呼び出しており、`readOrgId`を使っていない。つまり`readOrgId`は外部から呼ばれない限り死んだコードである可能性が高い。同じ目的のロジックが2箇所に存在し、片方だけ修正すると不整合が生じる。
**あるべき姿**: org ID 取得の責務を一箇所に集約する。`readOrgId`が外部で使われていなければ削除し、JS側の4段階フォールバックに統一する。

### 2. parseUnixTimestamp が parseResetsAt と機能重複している

**現状**: `parseResetsAt`(L221-228)は Unix timestamp (Double/Int) と ISO 8601 文字列の両方を処理する。`parseUnixTimestamp`(L231-239)は Unix timestamp のみを処理する。`parseResetsAt`の前半部分と`parseUnixTimestamp`は完全に同じロジック。
**本質**: `parseUnixTimestamp`は`parseResetsAt`のサブセットであり、呼び出し元がなければ不要。あっても`parseResetsAt`に委譲すべき。
**あるべき姿**: `parseUnixTimestamp`を削除するか、`parseResetsAt`が内部で`parseUnixTimestamp`を呼ぶ形に整理する。
