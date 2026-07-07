# code

All source code for ClaudeUsageTracker: the macOS app, its build/deploy tooling,
and throwaway investigation code.

## Directory Structure

```
code/
├── app/          # Xcode project + Swift sources
│   ├── ClaudeUsageTracker/         # Main macOS app (SwiftUI, MenuBarExtra)
│   ├── ClaudeUsageTrackerShared/   # Code shared between app and widget
│   ├── ClaudeUsageTrackerWidget/   # WidgetKit extension
│   └── ClaudeUsageTracker.xcodeproj
├── tools/        # Python build/deploy pipeline (build_and_install.py,
│                 #   rollback.py, publish.sh, check_notarization.sh, lib/)
└── prototypes/   # Throwaway investigation code (private; one subdir per topic)
```

## Naming convention

Source-mirrored — file and directory names mirror the code structure they
implement. **No date prefix** (these are living source, not dated documents).
`prototypes/` groups each investigation under its own topic subdirectory (flat
files directly under `prototypes/` are discouraged).
