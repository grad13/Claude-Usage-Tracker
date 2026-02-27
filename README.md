# ClaudeUsageTracker

macOS menu bar app for monitoring Claude Code usage limits in real time.

## Features

- Real-time 5h / 7d usage percentage display in the menu bar
- Usage history graphs (area chart)
- Analysis page with detailed usage timeline (Chart.js)
- JSONL-based cost estimation (Predict)
- WidgetKit widgets (small / medium / large)
- Auto-refresh every 5 minutes (configurable)
- Start at Login support

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

The data-fetching approach (using WKWebView browser sessions to access internal APIs) is inspired by [AgentLimits](https://github.com/nicedmng/AgentLimits).

## License

MIT
