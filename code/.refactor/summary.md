<!-- meta: created=2026-03-15 updated=2026-03-15 -->
# tools/ リファクタリング分析サマリー

## 対象

`code/tools/` 全8ファイル（テスト除外）

## 判定結果

| File | Lines | Judgment | Issues |
|------|-------|----------|--------|
| tools/build_and_install.py | 427 | **should** | mtime-fallback, mixed-responsibilities(×2), redundant-deregister, confusing-runner-api, magic-sleeps |
| tools/lib/runner.py | 29 | **should** | check/allow_fail 2フラグの意味論が冗長 |
| tools/lib/data_protection.py | 155 | clean | 単一責務、3層防御が適切 |
| tools/lib/db_backup.py | 59 | clean | 単一責務、センチネル値の使い方が適切 |
| tools/lib/launchservices.py | 68 | clean | 単一責務、lsregister操作に限定 |
| tools/lib/version.py | 23 | clean | 単一責務、簡潔 |
| tools/lib/__init__.py | 0 | (skip) | パッケージマーカー |
| tools/rollback.py | 124 | clean | 単一責務、atomic swapパターン適切 |

## should: 2件 / clean: 5件 / must: 0件

## 使われ方（ワークフロー全体像）

```
/deploy スキル → python3 ./code/tools/build_and_install.py
                 ├── lib/db_backup.py    (DB バックアップ)
                 ├── lib/data_protection.py (settings.json 保護)
                 ├── lib/runner.py       (subprocess 実行)
                 ├── lib/launchservices.py (LS 登録/解除)
                 └── lib/version.py      (バージョン取得)

手動ロールバック → python3 rollback.py <version>
                   ├── lib/runner.py
                   └── lib/launchservices.py

/publish スキル → build_and_install.py を使わない（xcodebuild archive を直接実行）
```

## 問題の本質

**lib/ は clean。問題は build_and_install.py のオーケストレーション層に集中している。**

過去のバグ5件中5件が build_and_install.py に起因:
- xctest 削除後の再署名漏れ → widget 真っ黒化
- `--deep` が entitlements を剥がす
- ゴースト LS 登録のパターン不足
- Scheme の buildForTesting="YES" が全バグの起点
- `find_derived_data_dir()` が別プロジェクトの DerivedData を返す

runner.py の check/allow_fail 冗長性は build_and_install.py の可読性を下げる間接的要因。

## 既存計画との関係

**`_documents/plan/2026-03-15-refactor-tools.md` に15ステップの詳細計画が既に存在。**
ただし plan/README.md のアクティブ計画リストには未登録。

## 詳細

- `code/.refactor/should/tools/build_and_install.py.md` — 6問題点の詳細分析
- `code/.refactor/should/tools/lib/runner.py.md` — check/allow_fail問題の詳細分析
