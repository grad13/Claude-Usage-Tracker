<!-- meta: created=2026-02-21 updated=2026-02-23 checked=never -->
# Changelog

## [0.5.1] - 2026-02-23

### Changed

- **グラフ: back-fill 廃止 + no-data グレー塗り**: データ未取得期間を最寄り値で引き延ばす back-fill を廃止。代わりにデータなし区間（ウィンドウ開始〜最初の取得、最後の取得〜現在時刻）を薄いグレー (`white.opacity(0.06)`) で塗りつぶし、データ有無を視覚的に区別
- **パーセントテキスト配置改善**: マーカーの上（エリアフィルと反対側）をデフォルトに変更。上端14px以内のときだけ下に表示。エリアフィルとの重なりを解消

## [0.5.0] - 2026-02-23

### Fixed

- **API フォーマット対応**: Format A (`five_hour`/`seven_day` + `utilization`) をサポート。Format B (`windows`/`5h`/`7d`) と自動判定
- **SnapshotStore: Keychain → ファイル**: macOS Widget Extension の sandbox 制約で Keychain が不安定なため、App Group ファイル (`snapshot.json`) に変更
- **Widget 描画修正**: `.containerBackground(.fill.tertiary)` → `.clear` に変更（`.fill.tertiary` が Canvas 描画を覆っていた）
- **NULL データ防止**: `UsageStore.save()` にコードガード追加 + CREATE TABLE に CHECK 制約。起動時に既存 NULL 行を自動削除する migration 追加

### Added

- テスト 36 件追加（310 件合計）: Fetcher 15、ViewModel 8、UsageStore 3、SnapshotStore 10

## [0.3.1] - 2026-02-22

### Changed

- **Org ID 取得をフォールバックレスに**: JS 内 4 段階フォールバック（cookie → performance API → HTML regex → `/api/organizations`）を完全除去。Swift 側で `WKHTTPCookieStore` から `lastActiveOrg` cookie を直接読取し、`callAsyncJavaScript(arguments:)` で JS に渡す方式に変更。JS は ~60 行 → 12 行に簡素化
- **Small ウィジェット**: テキスト表示（パーセント + 残り時間）→ WidgetMiniGraph グラフ表示（5h / 7d 上下配置）に変更

### Added

- `CLAUDE.md`（ルート）: プロジェクト開発ルール・プロセス
- `README.md`（ルート）: プロジェクト概要 + AgentLimits クレジット

### Removed

- `/api/organizations` 呼出（Approach A）を完全除去
- JS 内の org ID 取得関数 4 つ（`readCookieValue`, `findOrgIdFromResources`, `findOrgIdFromHtml`, `findOrgIdFromApi`）を削除

## [0.3.0] - 2026-02-22

### Added (Phase 3: ウィジェット)

- **macOS WidgetKit ウィジェット**: Small / Medium / Large の3サイズ対応
  - Small: 5h / 7d パーセント数値 + リセットまでの残り時間
  - Medium: 5h / 7d グラフ左右並び + パーセント + 残り時間（1行）
  - Large: セクション別グラフ（大）+ パーセント + 残り時間 + Est. コスト
- **WeatherCCShared フレームワーク**: メインアプリとウィジェット間の共有コード
  - `UsageSnapshot` / `HistoryPoint` データモデル
  - `SnapshotStore` — App Group ファイル経由でスナップショットを共有
  - `AppGroupConfig` — App Group ID 定数
- **App Group ファイル共有**: App Group コンテナ内の `snapshot.json` でアプリ ↔ ウィジェット間のデータ共有を実現
- **App Sandbox 有効化**: メインアプリを sandbox 化（Keychain 共有の前提条件）
  - `com.apple.security.network.client` — HTTP 通信用
  - `com.apple.security.temporary-exception.files.absolute-path.read-only` — JSONL 読み取り用
- **build-and-install.sh**: ビルド → `/Applications` コピー → LaunchServices 登録 → chronod 再起動 → 起動の自動化スクリプト

### Changed

- **グラフ描画改善**: ウィンドウ開始前のデータポイントをスキップ（リセット前の古いデータが左端に表示される問題を修正）
- **グラフ現在時刻延長**: 最後のデータポイントから現在時刻まで水平にエリアを延長（ウィジェットグラフ）
- **isLoggedIn 対応**: ログアウト時にグラフ背景を赤 (#3A1010) に変更（メニューバーと統一）

### Fixed

- WidgetMediumView の notFetchedView をデバッグ表示からクリーンな fallback に修正

## [Unreleased]

### Added (Phase 1 UI 仕上げ)

- **メニューバーミニグラフ**: 数値テキストを Canvas ベースのグラフに変更（5h / 7d 横並び、色分け: 緑 < 70%, オレンジ 70-90%, 赤 >= 90%）
- **残り時間表示**: ドロップダウンに "resets in Xh Ym" / "Xd Yh" 形式で残り時間を表示
- **Visit Usage Page ボタン**: デフォルトブラウザで claude.ai/settings/usage を開く

### Changed (Phase 1 UI 仕上げ)

- **UsageFetcher パース全面修正**: `json["five_hour"]["utilization"]` → `json["windows"]["5h"]` の `limit`/`remaining` から算出。`resets_at` を ISO 8601 → Unix 秒に変更
- **UsageResult に status 追加**: `fiveHourStatus` / `sevenDayStatus` フィールド（within_limit / approaching_limit / exceeded_limit）
- **UsageViewModel に時間計算追加**: `timeProgress()` / `remainingTimeText()` / 対応する computed properties
- 不要な ISO 8601 パーサ（`parseDate`, `formatterWithFractional`, `formatterNoFractional`, `trimFractionalSeconds`）を削除

### Added

- **Phase 2: JSONL 推定（Predict）** — ローカル JSONL ログからトークンコストを推定
  - `JSONLParser.swift` — JSONL ファイルの読み込み・パース・requestId 重複排除
  - `CostEstimator.swift` — モデル別コスト計算（Opus/Sonnet/Haiku）・ウィンドウ集計
  - `JSONLParserTests.swift` — 8テスト（パース、フィルタ、重複排除、エラーハンドリング）
  - `CostEstimatorTests.swift` — 11テスト（コスト計算、ウィンドウフィルタ、トークン内訳）
  - `docs/spec/phase2-spec.md` — Phase 2 仕様書

### Changed (Phase 1 改善 — agentlimits-approach-extract.md に基づく)

- **改善1**: OAuth ポップアップを `addSubview` → SwiftUI `.sheet()` モーダルに変更
- **改善2**: org ID 取得 + API 呼び出しを JS 1スクリプトに統合（Swift 側分岐を削除）
- **改善3**: フェッチ制御を `pendingFetch`（一度限り）→ `isAutoRefreshEnabled`（認証エラー時のみ無効化）に変更
- **改善4**: サインアウトを全削除 + Cookie 個別削除の二重削除方式に変更
- **改善5**: 日付パースを2段階 → 3段階（ミリ秒超の小数秒切り詰め）に拡張
- **改善6**: API レスポンスの生 JSON をデバッグビルドでログ出力
- `FetcherTests` に10テスト追加（日付パース3段階 + isAuthError）

### Changed (v0.1.0 からの変更)

- org ID 取得: `/api/organizations` API → Cookie (`lastActiveOrg`) + JS フォールバック
- デリゲート配置: LoginWebView 内 → UsageViewModel の WebViewCoordinator
- ログイン検出: フェッチ成功判定 → `sessionKey` Cookie 監視（`WKHTTPCookieStoreObserver`）
- ナビゲーション制限: usage ページのみ → claude.ai ドメイン全体
- ページ準備検出: KVO `isLoading` → `didFinish` デリゲート
- リダイレクト制御: 最大2回カウント → 5秒クールダウン
- Cookie ストア: `WKWebsiteDataStore(forIdentifier:)` → `.default()` に復帰
- LoginWebView: OAuth・ナビゲーション・リダイレクトのロジックを削除、薄いラッパーに簡素化

## [0.1.0] - 2026-02-21

### WeatherCC MVP

- メニューバー常駐アプリ（`5h: XX% / 7d: YY%` 表示）
- WKWebView で claude.ai ログイン（Google OAuth 対応）
- JavaScript 実行で usage API フェッチ
- 起動時バックグラウンド自動フェッチ
- ログイン後ページ読み込み完了時の自動フェッチ
- 5分間隔の定期自動リフレッシュ
- Sign In / Sign Out 切り替え
- ログイン後のナビゲーション制限（usage ページのみ）
- Start at Login（SMAppService）
- ClaudeLimits → WeatherCC にリネーム
