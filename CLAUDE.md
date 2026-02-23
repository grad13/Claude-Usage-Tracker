# WeatherCC

macOS menu bar app for Claude Code usage monitoring.

## Build & Test

```bash
xcodebuild -project src/WeatherCC.xcodeproj -scheme WeatherCC -destination 'platform=macOS' build
xcodebuild test -project src/WeatherCC.xcodeproj -scheme WeatherCC -destination 'platform=macOS'
```

## Rules

1. **作業前に docs/plans/overview.md を読む**
2. **コード変更前に plan mode で承認を得る**
3. **変更後は docs/CHANGELOG.md を更新する**
4. **日本語でコミュニケーションする**

## Structure

- Source: `src/WeatherCC/`
- Tests: `tests/WeatherCCTests/`
- Docs: `docs/` (not git-tracked)
- Scripts: `scripts/` (not git-tracked)

## Session Start

`docs/CLAUDE.md` → `docs/plans/overview.md` → 作業開始
