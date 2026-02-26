---
File: tests/WeatherCCTests/ViewModelTests.swift
Lines: 874
Judgment: must
Issues: [M2, OBS-1, OBS-2]
---

# ViewModelTests.swift

## 問題点

### 1. [M2] 500行超の巨大テストファイル

**現状**: 874行。モック定義（8-103行、約96行）+ テストクラス（108-874行、約766行）が1ファイルに集約されている。テストメソッドは40以上。
**本質**: テスト対象の `UsageViewModel` の責務が広い（statusText, settings, fetch, signOut, snapshot, widget reload, timeProgress）ため、テストも肥大化している。1ファイルに全てがあると、関連するテストの発見・メンテナンスが困難。
**あるべき姿**: 以下のように分割する:
  - `ViewModelTests+StatusText.swift` -- statusText 表示系（143-165, 403-470行）
  - `ViewModelTests+Settings.swift` -- toggleStartAtLogin, setRefreshInterval, setShow*, setChart*, setColorPreset（167-401行）
  - `ViewModelTests+Fetch.swift` -- fetch 成功/失敗/認証エラー/リカバリ（712-873行）
  - `ViewModelTests+SignOut.swift` -- signOut 状態クリア + snapshot + widget reload（272-298, 352-359, 580-598, 681-692行）
  - `ViewModelTests+TimeProgress.swift` -- timeProgress, remainingTimeText（300-334, 338-348, 473-501, 563-578行）
  - `ViewModelTests+Snapshot.swift` -- snapshot write + widget reload カウント（529-559, 664-708行）
  - `TestDoubles/ViewModelTestDoubles.swift` -- 全モック/スタブ定義（8-103行）

### 2. [OBS-1] ウィジェット描画ロジックのテストが ViewModel テストに混在

**現状**: `testWidgetGraphRenderability_variousSnapshotStates`（605-662行）が `WidgetMiniGraph` の描画判定ロジックを手動で再現してテストしている。
**本質**: これは ViewModel の振る舞いテストではなく、ウィジェットの描画ロジックの検証。ViewModel テストファイルに置く理由がない。テスト対象コードが別モジュール（ウィジェット）にあるため、将来ウィジェット側のロジックが変わっても、このテストは更新漏れしやすい。
**あるべき姿**: ウィジェットの描画ロジックテストとして `WidgetMiniGraphTests.swift` 等に移動するか、ウィジェット側にテストがあればそちらに統合する。

### 3. [OBS-2] 非同期テストで DispatchQueue.main.asyncAfter + wait パターンが多用

**現状**: 11箇所で `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` + `wait(for:timeout:2.0)` パターンが使われている（229-231, 537-538, 549-551, 589-590, 671-672, 685-686, 698-699, 729-730, 745-746, 764-765, 786-787行など）。
**本質**: 固定 0.5 秒の待ちは不安定テストの原因になり得る。CI 環境の負荷次第で 0.5 秒では足りない場合がある。また、全テスト実行時の累積待ち時間が 5.5 秒以上になる。
**あるべき姿**: async/await ベースのテストに移行し、明示的な待ちを排除する。あるいは XCTestExpectation を条件ベース（`asyncAfter` ではなく実際の完了を監視）で使う。
