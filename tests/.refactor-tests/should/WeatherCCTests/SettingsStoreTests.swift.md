# SettingsStoreTests.swift リファクタリング分析

## 該当ルール

### S6: 複数モジュールを1ファイルでテスト

**現状**: `ProductionSettingsIntegrityTests` クラスと `SettingsStoreTests` クラスが同一ファイルに存在。

- `ProductionSettingsIntegrityTests` は `WeatherCCShared` モジュール (`AppGroupConfig`) に依存
- `SettingsStoreTests` は `@testable import WeatherCC` モジュール (`SettingsStore`, `AppSettings`) に依存

**推奨**: `ProductionSettingsIntegrityTests` を別ファイル (`ProductionSettingsIntegrityTests.swift`) に分離する。これにより各テストファイルのモジュール依存が明確になる。
