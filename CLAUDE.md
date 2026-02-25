# WeatherCC

macOS menu bar app for Claude Code usage monitoring.

## Build & Test

```bash
xcodebuild -project code/WeatherCC.xcodeproj -scheme WeatherCC -destination 'platform=macOS' build
xcodebuild test -project code/WeatherCC.xcodeproj -scheme WeatherCC -destination 'platform=macOS'
```

## Rules

1. **作業前に documents/plan/overview.md を読む**
2. **コード変更前に plan mode で承認を得る**
3. **変更後は documents/CHANGELOG.md を更新する**
4. **日本語でコミュニケーションする**

## Structure

- Source: `code/WeatherCC/`
- Tests: `tests/WeatherCCTests/`
- Docs: `documents/` (not git-tracked)
- Scripts: `scripts/` (not git-tracked)

## Session Start

`documents/CLAUDE.md` → `documents/plan/overview.md` → 作業開始
