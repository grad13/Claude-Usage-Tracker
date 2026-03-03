---
File: tests/ClaudeUsageTrackerTests/AnalysisSchemeHandlerSupplementTests.swift
Lines: 767
Judgment: must
Issues: [M2, S6, S7]
---

# AnalysisSchemeHandlerSupplementTests.swift

## 問題点

### 1. [M2] ファイルが500行を超過（767行）

**現状**: 単一ファイルに767行のテストコードが格納されている。

**本質**: XCTest テストクラスのファイルサイズが大きすぎると、以下の課題が生じる：
- テストクラス内のメソッド検索・修正時に視認性が低下
- リファクタリング時の変更影響範囲の把握が困難
- CI/CD での並列実行効率が低下する可能性
- メンテナンスコストが増加

**あるべき姿**: 関連テストをグループ化し、各グループを複数ファイルに分割する（1ファイル あたり 250〜400行が目安）。

---

### 2. [S6] 複数モジュール領域を1ファイルでテスト

**現状**: 4つのテストクラスが1ファイルに混在：
- `AnalysisSchemeHandlerMetaJSONTests` — meta.json エンドポイント（UT-M01〜M05）
- `AnalysisSchemeHandlerQueryFilterTests` — クエリフィルタリング（UT-F01〜F04）
- `AnalysisSchemeHandlerHelperTests` — ヘルパー関数テスト（parseQueryParams, columnInt, serializeJSON）
- `AnalysisSchemeHandlerErrorHeaderTests` — エラーレスポンスヘッダ（400, 404, 500）

各クラスが異なる責任領域をテストしており、ビジネスロジック的に独立している。

**本質**: テストの責任分離が進んでいない。各領域が独立したテストファイルにあると：
- テスト実行が細粒度で制御でき、デバッグが容易
- 関連テストの追加時に該当ファイルだけ編集できる
- コードレビューでのフォーカスが明確

**あるべき姿**: 領域ごとにファイルを分割：
- `AnalysisSchemeHandlerMetaJSONTests.swift` — meta.json テスト
- `AnalysisSchemeHandlerQueryFilterTests.swift` — フィルタリングテスト
- `AnalysisSchemeHandlerHelperTests.swift` — ヘルパー関数テスト
- `AnalysisSchemeHandlerErrorHeaderTests.swift` — エラーハンドリングテスト

---

### 3. [S7] protocol conformance ではなく手書きモックを使用

**現状**: `MockSchemeTask` が手書きモック実装として利用されている（ファイル内で定義されていると推定）。`WKSchemeTask` protocol に対する protocol conformance ベースの自動モック化ではなく、手書きオブジェクトでプロトコルをシミュレートしている。

例：
```swift
let task = MockSchemeTask(url: URL(string: "cut://meta.json")!)
handler.webView(WKWebView(), start: task)
XCTAssertTrue(task.didFinishCalled)
```

**本質**:
- 手書きモックは `protocol` 変更時に型安全性が失われる（コンパイルエラーではなく実行時エラー）
- モック実装とプロトコル定義の乖離が生じやすい
- テストの保守性が低下

**あるべき姿**: `@Protocol conformance` ベースのモックライブラリ（例：`Mockingbird`, `Swift Testing` の Mock 機能など）を活用し、プロトコル要件の自動検証を実装する。またはテストダブルとして専用の stub/spy を `struct` で実装し、型安全性を保証する。

