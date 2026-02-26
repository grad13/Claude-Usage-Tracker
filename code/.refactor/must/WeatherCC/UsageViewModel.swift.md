---
File: WeatherCC/UsageViewModel.swift
Lines: 678
Judgment: must
Issues: [God Object — 10以上の責務が1クラスに集中, Cookie管理ロジックの内包, 設定変更メソッドの羅列, デバッグログ基盤の埋め込み]
---

# UsageViewModel.swift

## 問題点

### 1. God Object — 10以上の責務が1クラスに集中

**現状**: UsageViewModel (596行) が以下の責務を全て持つ:
- UIバインディング (10-22行: 13個の@Publishedプロパティ)
- データ取得 (195-268行: fetch, fetchSilently, applyResult)
- コスト推定 (272-312行: fetchPredict, claudeProjectsDirectories)
- WebView管理 (319-338行: loadUsagePage, isOnUsagePage, canRedirect)
- Cookie観察 (342-371行: startCookieObservation, handleSessionDetected)
- ログインポーリング (375-388行: startLoginPolling)
- Cookieバックアップ/リストア (390-460行: backupSessionCookies, restoreSessionCookies, CookieData構造体)
- ポップアップ管理 (464-492行: checkPopupLogin, closePopup, handlePopupClosed)
- 設定管理 (496-531行: 7つのset*メソッド)
- サインアウト (533-567行: 全状態のリセット)
- 自動リフレッシュ (583-604行: startAutoRefresh, restartAutoRefresh)
- デバッグログ (80-97行: debug, logURL)

**本質**: ViewModelが「アプリ全体のコントローラー」になっている。認証フロー、データ永続化、ネットワーク、UI状態管理が密結合しており、どの責務の変更も他の全てに影響しうる。テストでは全ての依存をモックしなければならず、init に7つのプロトコルが注入されている (103-111行)。

**あるべき姿**: 責務ごとに分離する:
- `SessionManager` — Cookie観察、ログインポーリング、Cookie バックアップ/リストア、ポップアップ認証フロー
- `AutoRefreshScheduler` — タイマー管理、リフレッシュ間隔設定
- `PredictService` (既存の fetcher/tokenSync を使う薄いラッパー) — fetchPredict ロジック
- `UsageViewModel` — UIバインディングのみ、上記サービスを組み合わせる

### 2. Cookie管理ロジックの内包 (70行)

**現状**: 390-460行。CookieData構造体の定義、App Groupへのシリアライズ/デシリアライズ、期限切れフィルタリング、HTTPCookiePropertyKey の組み立てが全てViewModel内にある。

**本質**: Cookie の永続化はインフラ層の関心事。ViewModel が FileManager、JSONEncoder/Decoder、App Group パスの構築を直接行っている。Cookie 形式が変わればViewModelを修正する必要がある。

**あるべき姿**: `CookieBackupStore` (or similar) に抽出。プロトコル経由で注入すれば、テスト時にモック可能。

### 3. 設定変更メソッドの羅列パターン (496-531行)

**現状**: setRefreshInterval, toggleStartAtLogin, setShowHourlyGraph, setShowWeeklyGraph, setChartWidth, setHourlyColorPreset, setWeeklyColorPreset — 7つのメソッドが同じ「プロパティ変更 → settingsStore.save」パターンを繰り返す。

**本質**: 設定項目が増えるたびにViewModelにメソッドを追加する必要がある。DRY違反。また、一部のメソッド (setRefreshInterval, toggleStartAtLogin) は副作用を持つが、他は持たない。この差が明示されていない。

**あるべき姿**: 副作用のない設定は settings プロパティの didSet で自動保存。副作用のあるものだけ明示的メソッドとして残す。

### 4. デバッグログ基盤の埋め込み (80-97行)

**現状**: debug() メソッドとlogURL静的プロパティがViewModel内に定義。NSLog + ファイル書き込みのデュアル出力。ISO8601DateFormatterを毎回生成。

**本質**: ログ基盤はアプリ全体で共有されるべきユーティリティ。ViewModel固有ではない。また、ISO8601DateFormatter の毎回生成はパフォーマンス上の無駄（DateFormatterは生成コストが高い）。

**あるべき姿**: 共通の Logger ユーティリティに抽出。ViewModel は logger.debug() を呼ぶだけ。
