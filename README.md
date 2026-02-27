# ClaudeUsageTracker

macOS menu bar app for monitoring Claude Code usage limits — log, track, and analyze your usage trends.

## Why This Exists

Claude Code enforces 5-hour and 7-day usage limits, but the only way to check is to visit claude.ai manually. Several tools exist to show you the current usage percentage, but they give you a snapshot — you see where you are *right now*, not how you got there.

ClaudeUsageTracker logs your usage over time and provides three levels of detail to help you understand your usage patterns:

| | When you look | What you see |
|---|---|---|
| **Menu bar** | Always visible | At-a-glance trend graphs (5h / 7d) |
| **Widgets** | When you're curious | Concrete numbers — percentages, reset times, estimated cost |
| **Analysis** | When you want to dig in | Full timeline, cost breakdown, efficiency analysis |

## Features

### Menu bar
- 5h and 7d usage trend graphs, always visible in the menu bar
- Step-interpolated area charts with session boundaries and reset points
- Auto-refresh at configurable intervals (default: 5 min)

### Widgets (WidgetKit)
- Small / Medium / Large sizes for your desktop
- Current usage %, time until reset, estimated cost
- Trend graphs with session markers

### Analysis page
- **Usage** — 5h / 7d usage timeline with session segmentation and gap handling
- **Cost** — per-request estimated cost over time (from local JSONL logs)
- **Efficiency** — cost vs. quota scatter plot, time-of-day heatmap, KDE density curves
- **Cumulative** — running total of estimated cost
- Interactive Chart.js charts with crosshair tooltips and date range filtering

### Other
- Start at Login (SMAppService)
- Threshold-based alerts for weekly, hourly, and daily usage
- Customizable graph colors and widths

## Related Projects

| Project | Approach | What It Shows |
|---------|----------|---------------|
| [ClaudeMeter](https://github.com/eddmann/ClaudeMeter) | macOS menu bar, session key | Current usage % |
| [AgentLimits](https://github.com/Nihondo/AgentLimits) | macOS menu bar, WKWebView login | Current usage % + token heatmap |
| **ClaudeUsageTracker** | macOS menu bar, WKWebView login | Usage log → menu bar / widget / analysis |

These tools all monitor Claude Code's usage limits. Existing tools focus on showing where you are *right now*. ClaudeUsageTracker logs usage over time and provides three levels of detail — a menu bar graph for at-a-glance status, widgets for concrete numbers, and an analysis page for deeper trend exploration.

## Requirements

- macOS 14.0+
- Xcode 16+

## Build

```bash
xcodebuild -project code/ClaudeUsageTracker.xcodeproj \
  -scheme ClaudeUsageTracker \
  -destination 'platform=macOS' build
```

## Usage

1. Launch the app — menu bar shows `5h: -- / 7d: --`
2. Click "Sign In..." → log in to claude.ai
3. Data fetches automatically → `5h: XX% / 7d: YY%`
4. Auto-refreshes every 5 minutes (manual: Cmd+R)
5. Enable "Start at Login" for auto-launch

## How It Works

Uses a WKWebView to maintain a browser session with claude.ai, then calls the internal usage API via JavaScript injection. No OAuth tokens or API keys are stored — authentication relies entirely on the browser session cookies.

## Acknowledgments

The data-fetching approach (using WKWebView browser sessions to access internal APIs) is inspired by [AgentLimits](https://github.com/Nihondo/AgentLimits).

## License

MIT
