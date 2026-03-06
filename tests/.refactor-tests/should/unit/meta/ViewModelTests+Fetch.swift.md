# ViewModelTests+Fetch.swift

- 行数: 259
- テストケース数: 13
- import: XCTest, ClaudeUsageTrackerShared, @testable ClaudeUsageTracker

## 該当ルール

### S8: 脆弱な非同期テスト待機パターン

5箇所で `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` + `wait(for:timeout:2.0)` の固定遅延パターンを使用。

該当テスト:
- `testFetch_usesInjectedFetcher` (L157-159)
- `testFetch_failure_setsError` (L174-176)
- `testFetch_authError_setsErrorAndDoesNotUpdateState` (L192-194)
- `testFetch_authErrorThenSuccess_recoversState` (L212-214, L228-230) -- 2箇所
- `testFetch_success_savesToUsageStore` (L250-252)

改善案: XCTestExpectation を fetch 完了コールバックに直接結びつけるか、async/await に移行して固定遅延を排除する。
