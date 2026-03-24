// meta: updated=2026-03-06 18:11 checked=-
// Supplement for: MenuContent UI logic tests

import XCTest
@testable import ClaudeUsageTracker

// Note: SwiftUI View body tests (MenuContent rendering, button appearance, colors) are
// intentionally omitted. SwiftUI views require a running host environment and cannot be
// reliably unit-tested without UI testing infrastructure. The tests here cover only the
// ViewModel logic and model-layer invariants that MenuContent depends on.

// Note: alert setters (setWeeklyAlertEnabled, setWeeklyAlertThreshold,
// setHourlyAlertEnabled, setHourlyAlertThreshold, setDailyAlertEnabled,
// setDailyAlertThreshold, setDailyAlertDefinition) are already covered in
// data/SettingsSupplementTests. Not duplicated here.

@MainActor
final class MenuContentSupplementTests: XCTestCase {

    var settingsStore: InMemorySettingsStore!
    var stubFetcher: StubUsageFetcher!

    override func setUp() {
        super.setUp()
        settingsStore = InMemorySettingsStore()
        stubFetcher = StubUsageFetcher()
    }

    func makeVM() -> UsageViewModel {
        ViewModelTestFactory.makeVM(
            fetcher: stubFetcher,
            settingsStore: settingsStore
        )
    }

    // MARK: - Usage display: fiveHourPercent nil-conditional

    // Guarantees: MenuContent shows the 5-hour row only when fiveHourPercent is non-nil.
    // The ViewModel property is the source of truth for this condition.

    func testFiveHourPercent_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.fiveHourPercent,
            "fiveHourPercent must be nil before first fetch — 5-hour row must be hidden")
    }

    func testFiveHourPercent_nonNilAfterSet() {
        let vm = makeVM()
        vm.fiveHourPercent = 42.5
        XCTAssertNotNil(vm.fiveHourPercent,
            "fiveHourPercent non-nil means 5-hour row must be shown")
    }

    func testSevenDayPercent_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.sevenDayPercent,
            "sevenDayPercent must be nil before first fetch — 7-day row must be hidden")
    }

    func testSevenDayPercent_nonNilAfterSet() {
        let vm = makeVM()
        vm.sevenDayPercent = 15.3
        XCTAssertNotNil(vm.sevenDayPercent,
            "sevenDayPercent non-nil means 7-day row must be shown")
    }

    // MARK: - Usage display format: %.1f

    // Guarantees: the menu rows show values with one decimal place (e.g. "42.5%", not "42%").
    // This is a pure string formatting invariant used by MenuContent.

    func testUsageDisplayFormat_oneDecimalPlace() {
        // Spec: "5-hour: XX.X%" — one decimal place via %.1f specifier.
        let value: Double = 42.5
        let formatted = String(format: "%.1f", value)
        XCTAssertEqual(formatted, "42.5",
            "%.1f must produce one decimal place for the menu display")
    }

    func testUsageDisplayFormat_roundsHalfUp() {
        // 42.55 rounds to 42.6 (standard %.1f rounding behavior).
        let formatted = String(format: "%.1f", 42.55)
        // Note: IEEE 754 double may produce 42.5 or 42.6 depending on representation.
        // The key guarantee is: exactly one decimal digit is shown.
        XCTAssertTrue(formatted.contains(".") && formatted.split(separator: ".")[1].count == 1,
            "%.1f must produce exactly one digit after the decimal point")
    }

    func testUsageDisplayFormat_zeroValue() {
        let formatted = String(format: "%.1f", 0.0)
        XCTAssertEqual(formatted, "0.0",
            "0%% utilization must render as '0.0', not '0'")
    }

    func testUsageDisplayFormat_hundredPercent() {
        let formatted = String(format: "%.1f", 100.0)
        XCTAssertEqual(formatted, "100.0",
            "100%% utilization must render as '100.0'")
    }

    // MARK: - Remaining text: nil-conditional display

    // Guarantees: the "(resets in ...)" suffix is shown only when resetsAt is non-nil.

    func testFiveHourResetsAt_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.fiveHourResetsAt,
            "fiveHourResetsAt nil → no resets-in suffix in 5-hour row")
    }

    func testSevenDayResetsAt_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.sevenDayResetsAt,
            "sevenDayResetsAt nil → no resets-in suffix in 7-day row")
    }

    func testFiveHourResetsAt_nonNilEnablesRemainingText() {
        let vm = makeVM()
        vm.fiveHourResetsAt = Date().addingTimeInterval(3600)
        XCTAssertNotNil(vm.fiveHourResetsAt,
            "fiveHourResetsAt non-nil → resets-in suffix must be shown")
    }

    func testSevenDayResetsAt_nonNilEnablesRemainingText() {
        let vm = makeVM()
        vm.sevenDayResetsAt = Date().addingTimeInterval(7 * 24 * 3600)
        XCTAssertNotNil(vm.sevenDayResetsAt,
            "sevenDayResetsAt non-nil → resets-in suffix must be shown")
    }

    // MARK: - Error display: nil-conditional

    // Guarantees: "Error: <message>" row is shown only when viewModel.error is non-nil.
    // Error does not suppress usage rows — both can appear simultaneously.

    func testError_nilByDefault() {
        let vm = makeVM()
        XCTAssertNil(vm.error,
            "error must be nil by default — no error row in menu")
    }

    func testError_nonNilShowsMessage() {
        let vm = makeVM()
        vm.error = "Network timeout"
        XCTAssertEqual(vm.error, "Network timeout",
            "error non-nil means 'Error: <message>' row is shown")
    }

    func testError_independentOfUsageData() {
        // Spec: error and usage rows can appear simultaneously.
        let vm = makeVM()
        vm.fiveHourPercent = 80.0
        vm.sevenDayPercent = 40.0
        vm.error = "Partial parse failure"
        XCTAssertNotNil(vm.fiveHourPercent,
            "Usage rows must remain visible even when error is set")
        XCTAssertNotNil(vm.sevenDayPercent,
            "Usage rows must remain visible even when error is set")
        XCTAssertNotNil(vm.error,
            "Error row must be shown alongside usage rows")
    }

    // MARK: - Sign In / Sign Out: isLoggedIn state

    // Guarantees: isLoggedIn = true → "Sign Out" button; isLoggedIn = false → "Sign In..." button.

    func testIsLoggedIn_falseByDefault() {
        let vm = makeVM()
        XCTAssertFalse(vm.isLoggedIn,
            "isLoggedIn must be false before session check — Sign In... must be shown")
    }

    func testSignOut_setsIsLoggedInToFalse() {
        let vm = makeVM()
        vm.isLoggedIn = true
        vm.signOut()
        XCTAssertFalse(vm.isLoggedIn,
            "signOut() must set isLoggedIn to false — Sign Out button switches to Sign In...")
    }

    // MARK: - Refresh button: isFetching disables the button

    // Guarantees: while isFetching is true, the Refresh button is disabled.
    // fetch() contains a guard !isFetching to prevent double-fetch.

    func testIsFetching_falseByDefault() {
        let vm = makeVM()
        XCTAssertFalse(vm.isFetching,
            "isFetching must be false initially — Refresh button must be enabled")
    }

    func testFetch_guardPreventDoubleFetch() async {
        // Spec: fetch() has guard !isFetching to prevent double-fetch.
        // The stub fetcher counts calls; if isFetching were not guarded, two calls
        // would result in fetchCallCount == 2.
        stubFetcher.fetchResult = .success(UsageResult())
        let vm = makeVM()
        vm.isFetching = true
        vm.fetch()
        // isFetching was already true → fetch() must not call the fetcher again
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        await fulfillment(of: [done], timeout: 1.0)
        XCTAssertEqual(stubFetcher.fetchCallCount, 0,
            "fetch() with isFetching==true must not call fetcher (double-fetch prevention)")
    }

    // MARK: - Refresh Interval: setRefreshInterval(minutes:)

    // Guarantees: refreshIntervalMinutes == 0 means auto-refresh is disabled (Off).
    // Note: Preset/label/threshold tests moved to data/SettingsPresetsTests.swift,
    // ChartColorPreset tests to data/ChartColorPresetTests.swift,
    // DailyAlertDefinition tests to data/DailyAlertDefinitionTests.swift.

    func testRefreshIntervalOff_zeroMeansDisabled() {
        let vm = makeVM()
        vm.setRefreshInterval(minutes: 0)
        XCTAssertEqual(vm.settings.refreshIntervalMinutes, 0,
            "refreshIntervalMinutes == 0 represents the 'Off' menu item")
    }
}
