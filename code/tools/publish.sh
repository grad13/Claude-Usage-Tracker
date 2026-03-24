#!/bin/bash
# meta: updated=2026-03-16 06:47 checked=-
set -e

# local ブランチにいることを確認
current=$(git branch --show-current)
if [ "$current" != "local" ]; then
  echo "Error: must be on local branch"; exit 1
fi

# 未コミット変更がないことを確認
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: uncommitted changes exist. Commit or stash first."; exit 1
fi

# main に切り替え
git checkout main

# local から公開ファイルのみ同期（ホワイトリスト方式）
# NOTE: .gitignore は同期しない（ブランチごとに個別管理）
# NOTE: code/.face/ は code/ に含まれるため個別指定不要
git checkout local -- code/ documents/spec/ documents/images/ \
  documents/CHANGELOG.md \
  tests/ README.md LICENSE .github/

# ホワイトリストに含まれるが .gitignore で除外されるファイルを unstage（安全策）
ignored=$(git ls-files --cached --ignored --exclude-standard)
if [ -n "$ignored" ]; then
  echo "$ignored" | xargs git rm --cached -r
fi

# 変更があればコミット
if ! git diff --cached --quiet; then
  git commit -m "sync from local"
fi

# push
git push origin main

# local に戻る
git checkout local
