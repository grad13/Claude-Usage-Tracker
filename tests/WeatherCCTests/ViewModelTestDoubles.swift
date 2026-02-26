import XCTest
import WebKit
import WeatherCCShared
@testable import WeatherCC

// MARK: - In-Memory Test Implementations

final class InMemorySettingsStore: SettingsStoring {
    var current = AppSettings()
    func load() -> AppSettings { current }
    func save(_ settings: AppSettings) { current = settings }
}

final class InMemoryUsageStore: UsageStoring {
    var savedResults: [UsageResult] = []
    var historyToReturn: [UsageStore.DataPoint] = []
    func save(_ result: UsageResult) { savedResults.append(result) }
    func loadHistory(windowSeconds: TimeInterval) -> [UsageStore.DataPoint] { historyToReturn }
}

final class InMemorySnapshotWriter: SnapshotWriting {
    struct FetchRecord {
        let timestamp: Date
        let fiveHourPercent: Double?
        let sevenDayPercent: Double?
        let fiveHourResetsAt: Date?
        let sevenDayResetsAt: Date?
        let isLoggedIn: Bool
    }
    struct PredictRecord {
        let fiveHourCost: Double?
        let sevenDayCost: Double?
    }

    var savedFetches: [FetchRecord] = []
    var savedPredicts: [PredictRecord] = []
    var signOutCount = 0

    func saveAfterFetch(
        timestamp: Date,
        fiveHourPercent: Double?, sevenDayPercent: Double?,
        fiveHourResetsAt: Date?, sevenDayResetsAt: Date?,
        isLoggedIn: Bool
    ) {
        savedFetches.append(FetchRecord(
            timestamp: timestamp,
            fiveHourPercent: fiveHourPercent,
            sevenDayPercent: sevenDayPercent,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
            isLoggedIn: isLoggedIn
        ))
    }

    func updatePredict(fiveHourCost: Double?, sevenDayCost: Double?) {
        savedPredicts.append(PredictRecord(
            fiveHourCost: fiveHourCost,
            sevenDayCost: sevenDayCost
        ))
    }

    func clearOnSignOut() { signOutCount += 1 }
}

final class InMemoryWidgetReloader: WidgetReloading {
    var reloadCount = 0
    func reloadAllTimelines() { reloadCount += 1 }
}

final class StubUsageFetcher: UsageFetching {
    var fetchResult: Result<UsageResult, Error> = .success(UsageResult())
    var hasValidSessionResult = false
    var fetchCallCount = 0
    var hasValidSessionCallCount = 0

    @MainActor func fetch(from webView: WKWebView) async throws -> UsageResult {
        fetchCallCount += 1
        return try fetchResult.get()
    }
    @MainActor func hasValidSession(using webView: WKWebView) async -> Bool {
        hasValidSessionCallCount += 1
        return hasValidSessionResult
    }
}

final class InMemoryTokenSync: TokenSyncing, @unchecked Sendable {
    func sync(directories: [URL]) {}
    func loadRecords(since cutoff: Date) -> [TokenRecord] { [] }
}

final class InMemoryLoginItemManager: LoginItemManaging {
    var enabledCallCount = 0
    var disabledCallCount = 0
    var lastEnabled: Bool?
    var shouldThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error = shouldThrow { throw error }
        lastEnabled = enabled
        if enabled { enabledCallCount += 1 }
        else { disabledCallCount += 1 }
    }
}
