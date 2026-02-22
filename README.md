<!-- meta: created=2026-02-21 updated=2026-02-21 checked=never -->
# WeatherCC

macOS メニューバーアプリ。Claude Code の使用量リミットをリアルタイム監視。

## 要件

- macOS 14.0+
- Xcode 16+

## ビルド

```bash
xcodebuild -scheme WeatherCC -destination 'platform=macOS' build
```

## 使い方

1. アプリ起動 → メニューバーに `5h: -- / 7d: --`
2. 「Sign In...」→ claude.ai にログイン
3. 自動でデータ取得 → `5h: XX% / 7d: YY%`
4. 以降5分ごとに自動更新（手動: ⌘R）
5. 「Start at Login」で macOS ログイン時に自動起動

## Acknowledgments

データ取得のアプローチ（WKWebView のブラウザセッションを利用した内部 API アクセス）は [AgentLimits](https://github.com/nicedmng/AgentLimits) を参考にしています。

## License

MIT
