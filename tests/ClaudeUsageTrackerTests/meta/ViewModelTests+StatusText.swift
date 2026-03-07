import XCTest
@testable import ClaudeUsageTracker

// MARK: - ViewModelTests + StatusText

extension ViewModelTests {

    // MARK: - statusText

    func testStatusText_noData() {
        let vm = makeVM()
        XCTAssertEqual(vm.statusText, "5h: -- / 7d: --")
    }

    func testStatusText_withData() {
        let vm = makeVM()
        vm.fiveHourPercent = 42.7
        vm.sevenDayPercent = 15.3
        XCTAssertEqual(vm.statusText, "5h: 43% / 7d: 15%")
    }

    func testStatusText_partialData_fiveHourOnly() {
        let vm = makeVM()
        vm.fiveHourPercent = 8.0
        XCTAssertEqual(vm.statusText, "5h: 8% / 7d: --")
    }

    func testStatusText_partialData_sevenDayOnly() {
        let vm = makeVM()
        vm.sevenDayPercent = 6.0
        XCTAssertEqual(vm.statusText, "5h: -- / 7d: 6%")
    }

    // MARK: - statusText Rounding

    func testStatusText_rounding() {
        let vm = makeVM()
        vm.fiveHourPercent = 99.5
        vm.sevenDayPercent = 0.4
        XCTAssertEqual(vm.statusText, "5h: 100% / 7d: 0%")
    }

    // MARK: - statusText Exact Boundaries

    func testStatusText_exactZeroPercent() {
        let vm = makeVM()
        vm.fiveHourPercent = 0.0
        vm.sevenDayPercent = 0.0
        XCTAssertEqual(vm.statusText, "5h: 0% / 7d: 0%")
    }

    func testStatusText_exactHundredPercent() {
        let vm = makeVM()
        vm.fiveHourPercent = 100.0
        vm.sevenDayPercent = 100.0
        XCTAssertEqual(vm.statusText, "5h: 100% / 7d: 100%")
    }
}
