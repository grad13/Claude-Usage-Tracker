---
File: ClaudeUsageTracker/UsageViewModel+Session.swift
Lines: 201
Judgment: should
Issues: [fallback polling, cookie backup/restore as inline logic]
---

# UsageViewModel+Session.swift

## 問題点

### 1. Login Polling が Timer ベースの fallback

**現状**: L43-58。SPA navigation が `didFinish` を発火しないケースの補償として、3秒間隔の `Timer.scheduledTimer` でセッション有無をポーリングしている。コメント自体が "fallback for SPA navigation that doesn't trigger didFinish" と明記。
**本質**: Cookie Observer (L12-26) が正系のセッション検知手段だが、それだけでは SPA 遷移を捕捉できないため、タイマーポーリングという補償メカニズムが必要になっている。正系が機能すれば不要なコードが常時動く構造。
**あるべき姿**: セッション検知の正系・補系を明確に分離し、fallback が必要な条件（SPA 遷移中のみ）でだけ起動するようにする。または WKWebView の `evaluateJavaScript` で SPA のルート変更を監視する JavaScript injection に置き換え、ポーリングを廃止する。

### 2. Cookie Backup/Restore のファイルパス構築がインライン

**現状**: L74-95 (backup) と L98-130 (restore) で、App Group コンテナの `Library/Application Support/{appName}/session-cookies.json` パスを毎回手組みしている。`CookieData` 構造体もこの extension 内に定義 (L64-71)。
**本質**: Cookie の永続化先パスと Codable モデルが ViewModel extension に埋め込まれている。パスの一貫性はこのファイル内の二箇所の一致に依存しており、別の場所から同じバックアップを読みたい場合に再利用できない。
**あるべき姿**: `SessionCookieStore` のような専用型に Cookie の保存・復元・パス解決を集約し、ViewModel はそれを呼ぶだけにする。
