# tools/ リファクタリング分析サマリー

実行日: 2026-03-04

## 結果一覧

| ファイル | 行数 | 判定 |
|----------|------|------|
| test-build-install.sh | 468 | should |
| build-and-install.sh | 182 | should |
| lib/data-protection.sh | 64 | clean |
| rollback.sh | 56 | clean |

## should（2件）

### test-build-install.sh (468行)

1. **バイナリバックアップロジックの3重複** — Test 6/7/8 で13行のバックアップロジックが3箇所にコピー
2. **アサーション方式の不統一** — `assert_eq` 関数があるのに手動 if/else が約6箇所
3. **5つの独立テスト対象が1ファイルに混在** — 行消失検出SQL、DBローテーション、バイナリバックアップ、rollback.sh、data-protection.sh

### build-and-install.sh (182行)

1. **責務混在** — 7つの責務がトップレベルのインラインコードとして並び、関数化なし
2. **重複コード** — LaunchServices DerivedData登録解除ループが2箇所でほぼ同一
3. **旧名クリーンアップの散在** — WeatherCCからのリネーム移行コードが3箇所に分散

## clean（2件）

- lib/data-protection.sh (64行) — 単一責務、適切な関数分離
- rollback.sh (56行) — 単一責務、適切なサイズ

## 構造的所見: bashスクリプトの限界

tools/ の問題は個別ファイルの品質だけでなく、**bash自体の構造的限界**が病理の根源:

- **テスト可能性の低さ**: bash関数のユニットテストは困難。test-build-install.sh が468行に膨張するのはテストフレームワークの不在が原因
- **コード再利用の困難さ**: `source` による結合は脆弱。lib/ への切り出しは始まっているが、bashの名前空間管理は本質的に弱い
- **型安全性ゼロ**: パス操作やバージョン文字列操作でサイレントに壊れるリスクが常にある

### 選択肢

1. **bash のまま改善** — 関数化、lib/ 分割、テストヘルパー整備。効果は限定的
2. **Swift スクリプト化** — プロジェクト自体がSwift。xcodeproj操作やplist編集はSwiftの方が型安全。ただし移行コスト大
3. **Makefile + bash関数lib** — ビルドタスクはMakefileで定義、複雑なロジックはlib/に関数として切り出す。最小変更で改善
