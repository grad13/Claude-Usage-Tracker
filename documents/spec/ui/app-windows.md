---
updated: 2026-03-16 06:59
checked: -
Deprecated: -
Format: spec-v2.1
Source: code/app/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift
---

# App Windows, Menu Bar Label, and Graph UI

## 0. Meta

| Source | Runtime |
|--------|---------|
| code/app/ClaudeUsageTracker/ClaudeUsageTrackerApp.swift | macOS |

| Field | Value |
|-------|-------|
| Related | spec/meta/architecture.md |
| Test Type | - |

## Window Definitions

The `body` of ClaudeUsageTrackerApp defines three Scenes:

| Scene | Window ID | Default Size | Content |
|-------|-----------|--------------|---------|
| `MenuBarExtra` | none | none | Menu bar resident UI (MenuContent + MenuBarLabel) |
| `Window("ClaudeUsageTracker — Sign In")` | `"login"` | 900 x 700 pt | LoginWindowView (OAuth login) |
| `Window("ClaudeUsageTracker — Analysis")` | `"analysis"` | 1200 x 800 pt | AnalysisWindowView (usage analysis) |

- The login window uses `id: "login"` and is opened via `openWindow(id: "login")`
- The Analysis window uses `id: "analysis"` with `.handlesExternalEvents(matching: ["analysis"])` for external event handling
- No Apple Event handler is used

## App Struct Definition

```swift
@main
struct ClaudeUsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra { MenuContent(viewModel: viewModel) } label: { MenuBarLabel(viewModel: viewModel) }
        Window("ClaudeUsageTracker — Sign In", id: "login") { LoginWindowView(viewModel: viewModel) }
            .defaultSize(width: 900, height: 700)
        Window("ClaudeUsageTracker — Analysis", id: "analysis") { AnalysisWindowView() }
            .defaultSize(width: 1200, height: 800)
            .handlesExternalEvents(matching: ["analysis"])
    }
}
```

## viewModel Ownership

`UsageViewModel` is owned by `ClaudeUsageTrackerApp` as a `@StateObject`. The same instance is passed to both `MenuContent` and `MenuBarLabel`. `AnalysisWindowView` does not receive the `viewModel`.

## AppDelegate Activation Policy

Sets `NSApp.setActivationPolicy(.accessory)` in `applicationDidFinishLaunching`.

- `.accessory`: Hides the app icon from the Dock and the app switcher
- Equivalent to setting `LSUIElement=true` in Info.plist, but applied at runtime
- Required for menu bar resident app behavior

`applicationDidFinishLaunching` performs exactly one action:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
}
```

## LoginWindowView Error Display UI

`LoginWindowView` displays an error message above the WebView when `viewModel.error` is non-nil.

| Attribute | Value |
|-----------|-------|
| Placement | Top of VStack(spacing: 0), above the WebView |
| Text color | `.red` |
| Font | `.caption` |
| Horizontal padding | `.horizontal` (default) |
| Vertical padding | 4pt |
| Display condition | `viewModel.error != nil` |

When no error exists, the text element is not rendered (conditional via `if let`).

## PopupSheetView UI Details

A sheet modal for OAuth popups. Presented from LoginWindowView's `.sheet()` modifier.

| Attribute | Value |
|-----------|-------|
| Display trigger | `viewModel.popupWebView != nil` |
| Dismiss action | `viewModel.closePopup()` + `viewModel.handlePopupClosed()` (both called on any dismiss path) |
| Minimum size | 520 x 640 pt (`minWidth: 520, minHeight: 640`) |
| VStack spacing | 12pt |
| Padding | `.padding()` (default value) |

**Layout structure**:

```
VStack(spacing: 12)
├── HStack
│   ├── Spacer
│   └── Button("Close")   ← Right-aligned close button
└── PopupWebViewWrapper    ← WKWebView for OAuth
```

The Close button is positioned at the top right and invokes the `onClose` closure (`viewModel.closePopup()`) when pressed.

## PopupWebViewWrapper

A thin WKWebView wrapper conforming to `NSViewRepresentable`.

| Attribute | Value |
|-----------|-------|
| Protocol | `NSViewRepresentable` |
| Input | `webView: WKWebView` (externally provided instance) |
| `makeNSView` | Returns the provided `webView` as-is |
| `updateNSView` | No-op (empty implementation) |

Follows the same pattern as `LoginWebView` (the main WebView wrapper) but displays a separate WebView instance for popups. Used exclusively within `PopupSheetView`. Does not manage WebView lifecycle or configure delegates.

## Menu Bar Label: Graph/Text Switching Logic

`MenuBarLabel` dynamically switches between graph display and text display based on settings.

### Switching Condition

When both `settings.showHourlyGraph` and `settings.showWeeklyGraph` are `false`, a text label (`viewModel.statusText`) is displayed instead of graphs. If either is `true`, graph display via `MenuBarGraphsContent` is used.

```
graphCount = (showHourlyGraph ? 1 : 0) + (showWeeklyGraph ? 1 : 0)

graphCount > 0 → MenuBarGraphsContent (graph display)
graphCount == 0 → Text(statusText) (text display)
```

### Text Fallback Display

- Font: `.system(size: 11, weight: .medium)`
- Color: `colorScheme == .dark ? .white : .black` (adapts to system appearance)

## Graph-Related Settings (AppSettings)

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `showHourlyGraph` | `Bool` | `true` | Show/hide the 5h graph |
| `showWeeklyGraph` | `Bool` | `true` | Show/hide the 7d graph |
| `chartWidth` | `Int` | `48` | Width of each graph (pt). Validation range: 12-120, presets: [12, 24, 36, 48, 60, 72] |
| `hourlyColorPreset` | `ChartColorPreset` | `.blue` | Area color for the 5h graph |
| `weeklyColorPreset` | `ChartColorPreset` | `.pink` | Area color for the 7d graph |

### ChartColorPreset

Defined as `enum ChartColorPreset: String, CaseIterable, Codable` with 7 color presets.

| case | displayName | RGB |
|------|-------------|-----|
| `blue` | Blue | (100, 180, 255) |
| `pink` | Pink | (255, 130, 180) |
| `green` | Green | (70, 210, 80) |
| `teal` | Teal | (0, 210, 190) |
| `purple` | Purple | (150, 110, 255) |
| `orange` | Orange | (255, 160, 60) |
| `white` | White | (230, 230, 230) |

## ImageRenderer for Menu Bar Image Generation

`MenuBarLabel.renderGraphs()` converts a SwiftUI view into an `NSImage`.

### Rendering Pipeline

```
SwiftUI View (MenuBarGraphsContent or Text)
  → .environment(\.colorScheme, colorScheme)  ← explicit injection (ImageRenderer does not auto-propagate)
  → ImageRenderer(content:)
  → renderer.scale = 2.0 (Retina support)
  → renderer.cgImage
  → NSImage(cgImage:, size:)  ※ size = cgImage width/height divided by 2.0
  → Image(nsImage:) displayed in MenuBarExtra label
```

Note: `ImageRenderer` renders outside the SwiftUI view hierarchy, so `@Environment` values are not automatically propagated. `MenuBarLabel` explicitly reads `@Environment(\.colorScheme)` and injects it into the content via `.environment(\.colorScheme, colorScheme)`.

### Scale Configuration

- `renderer.scale = 2.0`: Renders at 2x for Retina display support
- NSImage `size` is set to `CGFloat(cgImage.width) / 2.0` x `CGFloat(cgImage.height) / 2.0` (converting back to logical pixels)

### Fallback Image

When `renderer.cgImage` returns `nil` (rendering failure), an empty `NSImage(size: NSSize(width: 80, height: 18))` is returned. Nothing is drawn; it becomes an 80x18pt transparent image.

## MiniUsageGraph Parameter Details

Complete set of parameters that `MenuBarGraphsContent` passes to `MiniUsageGraph`.

### 5h (Hourly) Graph

| Parameter | Value |
|-----------|-------|
| `history` | `viewModel.fiveHourHistory` |
| `windowSeconds` | `5 * 3600` (18,000 seconds) |
| `resetsAt` | `viewModel.fiveHourResetsAt` |
| `areaColor` | `settings.hourlyColorPreset.color` (default: blue) |
| `areaOpacity` | `0.7` |
| `divisions` | `5` |
| `chartWidth` | `CGFloat(settings.chartWidth)` (default: 48pt) |
| `isLoggedIn` | `viewModel.isLoggedIn` |

### 7d (Weekly) Graph

| Parameter | Value |
|-----------|-------|
| `history` | `viewModel.sevenDayHistory` |
| `windowSeconds` | `7 * 24 * 3600` (604,800 seconds) |
| `resetsAt` | `viewModel.sevenDayResetsAt` |
| `areaColor` | `settings.weeklyColorPreset.color` (default: pink) |
| `areaOpacity` | `0.65` |
| `divisions` | `7` |
| `chartWidth` | `CGFloat(settings.chartWidth)` (default: 48pt) |
| `isLoggedIn` | `viewModel.isLoggedIn` |

### Differences in Fixed Parameters

| Parameter | 5h | 7d | Reason |
|-----------|----|----|--------|
| `areaOpacity` | 0.7 | 0.65 | Slightly reduced for 7d to visually distinguish the longer timeframe |
| `divisions` | 5 | 7 | Number of time division lines (5 hours = 5 divisions, 7 days = 7 divisions) |
