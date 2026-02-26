---
File: WeatherCC/WeatherCCApp.swift
Lines: 522
Judgment: must
Issues: [責務混在 — 7つの責務が1ファイルに同居]
---

# WeatherCCApp.swift

## 問題点

### 1. 7つの責務が1ファイルに同居している

**現状**: 522行のファイルに以下の責務が混在している:
- App エントリポイント + Scene 定義 (L6-28, 23行)
- AppDelegate + URL ハンドリング (L32-47, 16行)
- メニューコンテンツ UI (L51-193, 143行)
- カスタムインターバル NSAlert プロンプト (L197-214, 18行)
- ログインウィンドウ + OAuth ポップアップ UI (L218-273, 56行)
- Analysis ウィンドウ + WKWebView (L277-301, 25行)
- メニューバーラベル + MiniUsageGraph Canvas 描画 (L305-521, 217行)

**本質**: 各責務が独立しているにもかかわらず1ファイルに詰め込まれているため、変更の影響範囲が不明瞭になる。特に `MiniUsageGraph`(146行の Canvas 描画ロジック)と `MenuContent`(143行のメニュー構築)は、それぞれ単独で意味のあるコンポーネントであり、他の責務と結合度が低い。

**あるべき姿**: 責務ごとにファイルを分割する。自然な分割案:
1. `WeatherCCApp.swift` — App + Scene 定義 + AppDelegate (L6-47)
2. `MenuContent.swift` — MenuContent + promptCustomInterval (L51-214)
3. `LoginWindowView.swift` — LoginWindowView + PopupSheetView + PopupWebViewWrapper (L218-273)
4. `AnalysisWindowView.swift` — AnalysisWindowView + AnalysisWebView (L277-301)
5. `MenuBarLabel.swift` — MenuBarLabel + MenuBarGraphsContent (L305-374)
6. `MiniUsageGraph.swift` — MiniUsageGraph (L376-521)
