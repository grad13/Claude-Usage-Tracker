# WeatherCC

macOS menu bar app for Claude Code usage monitoring.

## Build & Test

```bash
xcodebuild -project code/WeatherCC.xcodeproj -scheme WeatherCC -destination 'platform=macOS' build
xcodebuild test -project code/WeatherCC.xcodeproj -scheme WeatherCC -destination 'platform=macOS'
```

## Rules

1. **作業前に _documents/plan/README.md を読む**
2. **コード変更前に plan mode で承認を得る**
3. **変更後は _documents/CHANGELOG.md を更新する**
4. **日本語でコミュニケーションする**

## Structure

Convention: `_` prefix = not published to GitHub (`.gitignore`: `_*/`, `**/_*/`)

| Directory | Purpose |
|-----------|---------|
| `code/WeatherCC/` | アプリ本体のソースコード |
| `tests/WeatherCCTests/` | ユニットテスト |
| `code/_tools/` | ビルド・デプロイスクリプト（build-and-install.sh 等） |
| `code/_prototype/` | UI 検証用プロトタイプ（HTML, ローカルサーバー等） |
| `_documents/` | 仕様・計画・参考資料・変更履歴 |
| `_externals/` | 参考コード（AgentLimits 等、設計の参考用） |

## Session Start

`_documents/CLAUDE.md` → `_documents/plan/README.md` → 作業開始
