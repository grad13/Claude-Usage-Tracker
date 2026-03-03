# AnalysisWebViewIntegrationTests.swift - Refactor Analysis

## 判定: SHOULD Refactor

**行数**: 140行（M2 threshold 500行 未満）

### 該当する refactor 基準

#### S6: 複数モジュールを1テストファイルでテスト
ファイルが以下の複数の独立したモジュール/機能をテストしている:

1. **AnalysisSchemeHandler** — custom URL scheme ハンドラー
2. **AnalysisTestDB** — テストDB作成（usage.db, tokens.db）
3. **TestNavDelegate** — WKWebView navigation delegate（ページロード完了検知）
4. **WKWebView JavaScript 統合** — fetch() を通じた JSON 取得の実行時動作

これらは概念的に独立した機能であり、複数のテストクラスに分割すべき。

#### S7: 手書きのモックオブジェクト（protocol conformance ではなく実装）

**TestNavDelegate** が手書き実装されている:
```swift
let navDelegate = TestNavDelegate(onFinish: { navExpectation.fulfill() })
webView.navigationDelegate = navDelegate
```

`WKNavigationDelegate` protocol に対する手書き実装であり、mock オブジェクトとして機能している。
これは部分実装モックの典型例。

### 推奨される分割

- **AnalysisSchemeHandlerTests** — scheme handler の単体テスト
- **AnalysisWebViewIntegrationTests** — WKWebView × JavaScript × scheme handler の統合テスト
- **AnalysisTestDBTests**（必要に応じて）— テストDB作成の検証

### 現在のテスト覆域
- `testWKWebView_canFetchJsonViaSchemeHandler()` — scheme handler を通じた JSON fetch の正常系
- `testWKWebView_unknownPath_fetchThrows()` — 404 時の fetch() の例外動作

統合テストとして有効だが、複数責任が混在している状態。
