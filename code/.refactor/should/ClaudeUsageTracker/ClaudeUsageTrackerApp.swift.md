# ClaudeUsageTrackerApp.swift — Refactoring Analysis

**Classification**: `should` (Responsibility mixing + Fallback concerns)

## Current State (37 lines)
- Entry point app setup
- MenuBar scene configuration
- Two window definitions (Login, Analysis)
- Inline AppDelegate implementation

## Issues Identified

### 1. Responsibility Mixing (Primary Issue)
The file contains:
- **App responsibility**: Scene and window configuration
- **AppDelegate responsibility**: Application lifecycle management

Both are logically distinct concerns crammed into one file.

### 2. AppDelegate as Fallback
The AppDelegate is minimal (just `applicationDidFinishLaunching` to set accessory policy) but represents application-level lifecycle handling that should be separate from UI scene definition.

### 3. Inline Window Configuration
Window sizes and IDs are hardcoded inline:
```swift
Window("ClaudeUsageTracker — Sign In", id: "login") { ... }
    .defaultSize(width: 900, height: 700)

Window("ClaudeUsageTracker — Analysis", id: "analysis") { ... }
    .defaultSize(width: 1200, height: 800)
```

These could be extracted to named constants or a separate window configuration module.

## Refactoring Recommendations

### Must-Do
1. **Extract AppDelegate to separate file**: `AppDelegate.swift`
   - Move `AppDelegate` class out
   - Import as dependency in main app

### Should-Do (Incremental)
2. **Extract window configurations**: Create `WindowConfiguration.swift` or similar
   - Define window sizes as constants
   - Group window setup logic
   - Example:
     ```swift
     enum WindowConfiguration {
         static let login = (width: 900, height: 700)
         static let analysis = (width: 1200, height: 800)
     }
     ```

3. **Consider scene separation**: If more scenes are added, could extract scene definitions
   - `MenuBarScene.swift`
   - `LoginScene.swift`
   - `AnalysisScene.swift`

## Impact Assessment
- **Low complexity**: Simple refactoring
- **Low risk**: No logic changes, pure extraction
- **Benefit**: Clearer separation of concerns, easier to test AppDelegate, reusable window configurations

## Files to Create/Modify
- `AppDelegate.swift` (new)
- `ClaudeUsageTrackerApp.swift` (modified — remove AppDelegate)
- `WindowConfiguration.swift` (optional, nice-to-have)
